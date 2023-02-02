#Requires -Version 7.0
#Requires -PSEdition Core

using module "../../pkg/utils/auth-get.psm1"
using module "../../pkg/jenkins-msteams/jenkins.psm1"
using module "../../pkg/jenkins-msteams/notify.psm1"

param(      
    [Parameter(Mandatory)] 
    [Alias("ju", "user")]                                                                    
    [string] $JenkinsUser,

    [Parameter(Mandatory)] 
    [Alias("jp", "pwd")]                                                                     
    [string] $JenkinsPwd,

    [Parameter(Mandatory)] 
    [Alias("t")]   
    [ValidateSet("DevOps", "Manhattan", IgnoreCase = $true)]                                                                   
    [string[]] $Teams
)

class State {
    [Collections.Generic.List[Job]] $Jobs
}

## Logging - Transcription ##
if (-not (Test-Path -Path ../../logs)) {
    # Create logs directory
    try {
        New-Item -ItemType Directory -Path ../../ -Name logs -ErrorAction Stop
        Start-Transcript -Path "../../logs/events_$((Get-Date).ToString("dd-MM-yyyy_HH-mm-ss")).log"
        Write-Host ">> Created ../../logs/ directory"
    }
    catch {
        throw $_.Exception.Message
    }
}
else {
    try {
        Start-Transcript -Path "../../logs/events_$((Get-Date).ToString("dd-MM-yyyy_HH-mm-ss")).log"
        Write-Host ">> Removing old logs"
        # Remove old logs
        [object[]] $logs = (Get-ChildItem -Path ../../logs -File)
        [string] $prefix = "events_"
        [string] $postfix = ".log"

        [object[]] $logsToRemove = $logs.Where({ 
                [string] $date, [string] $time = $_.Name.Substring($prefix.Length, $_.Name.Length - ($prefix.Length + $postfix.Length)) -split ("_")
                [datetime] $fileDT = ([datetime]::ParseExact("$date $($time.Replace("-", ":"))", "dd-MM-yyyy HH:mm:ss", $null))
                [datetime] $today = Get-Date
                -not ($today.AddDays(-2) -le $fileDT)
            })
    
        if ($logsToRemove.Length -gt 0) {
            Remove-Item $logsToRemove.FullName
    
            Write-Host "`n#### Removed logs ####"
            $logsToRemove | Format-Table -AutoSize -Wrap Name, Length, LastWriteTime
            Write-Host "######################`n"
        }
        else {
            Write-Host ">> No logs to remove`n"
        }
    } 
    catch {
        Write-Error "Failed to remove old log files.`n$($_.Exception.Message)`n"
    }
}

## Constants ##
[string] $STATE_PATH = "./state.json"
[pscustomobject] $SETTINGS = (Get-Content -Raw "$PSScriptRoot/../../appsettings.json") | ConvertFrom-Json
[string] $JENKINS_ROOT_URL = ${env:JENKINS_URL}.TrimEnd("/").TrimEnd("\")
Write-Host "`nJENKINS_ROOT_URL : $JENKINS_ROOT_URL"

# Configure request headers 
[hashtable] $additionalHeaders = @{
    "Cache-Control" = "no-cache"
}

# Get the upstream job that triggered the manager job
[Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $json = (Send-AuthGet -user $JenkinsUser -password $JenkinsPwd -uri "$JENKINS_ROOT_URL/job/${env:JOB_NAME}/lastBuild/api/json" -additionalHeaders $additionalHeaders)
[PSCustomObject] $buildInfo = ConvertFrom-Json $json
[UpstreamJob] $upstreamJob = Get-UpstreamJob $buildInfo
Write-Host "`nUpstream job :`n    Name   : $($upstreamJob.Name)`n    Number : $($upstreamJob.Number)`n"

if (-not (Test-Path $STATE_PATH)) {
    # Get all upstream jobs
    [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $json = (Send-AuthGet -user $JenkinsUser -password $JenkinsPwd -uri "$JENKINS_ROOT_URL/job/${env:JOB_NAME}/api/json" -additionalHeaders $additionalHeaders)
    [PSCustomObject] $buildInfo = ConvertFrom-Json $json
    [string[]] $upstreamProjects = ($buildInfo.upstreamProjects.name).ForEach({ $_.ToLower() })
    [string[]] $jobOrder = ($buildInfo.description -split "`r`n" -split "`n").ForEach({ $_.Trim(" ").Trim("`t").ToLower() }).Where({ ($_.Length -gt 0) -and ($_ -notcontains "`n") })
    if ($upstreamProjects.Count -ne $jobOrder.Count) { 
        Write-Host ""
        Write-Host "`n[ERROR] `$upstreamProjects.Count -> $($upstreamProjects.Count) and `$jobOrder.Count -> $($jobOrder.Count) are not equal." 
        Write-Host "[UpstreamProjects] $($upstreamProjects)`n"
        Write-Host "[JobOrder] $($jobOrder)`n"
    }

    # Configure initial state
    [Collections.Generic.List[Job]] $jobs = [Collections.Generic.List[Job]]::new()
    $upstreamProjects.ForEach({
            $jobs.Add([Job]@{
                    Name        = $_
                    Finished    = $false
                    SequenceNumber = $jobOrder.IndexOf($_)
                })
        })
    $jobs = ($jobs | Sort-Object -Property SequenceNumber)

    if ($jobs.SequenceNumber -contains -1) {
        $jobs.ForEach({ if ($_.SequenceNumber -eq -1) { Write-Host "[ERROR] $($_.Name) has SequenceNumber $($_.SequenceNumber)" } })
        Write-Host "[ERROR] The job sequence will not be accurate, since the order could not be dertermined without error"
    }

    [State] $tempState = $([State]@{
            Jobs = $jobs
        })

    New-Item -Path $STATE_PATH -ItemType "file" -Value (ConvertTo-JSON $tempState) | Out-Null
}
[State] $state = (Get-Content -Raw -Path $STATE_PATH | ConvertFrom-Json)
Write-Host "
#### Starting state ####"
$state.Jobs | Format-Table -AutoSize -Wrap Name, Finished, SequenceNumber
Write-Host "########################"
Write-Host ""

[bool[]] $running = [bool[]]::new($state.Jobs.Count)

[hashtable] $buildInfoStorage = [hashtable]::new()

Write-Host ">> Checking upstream jobs ..."
for ($i = 0; $i -lt $state.Jobs.Count; $i++) {
    Write-Host "Job $i : "
    Write-Host " - Name      : $($state.Jobs[$i].Name)"
    Write-Host " - Finished  : $($state.Jobs[$i].Finished)"
    if (-not $state.Jobs[$i].Finished) {
        [string] $jobUrl = "$JENKINS_ROOT_URL/job/$($state.Jobs[$i].Name)"
        [string] $buildUrl = "$jobUrl/lastBuild"
        Write-Host " - Job URL   : $jobUrl"
        Write-Host " - build URL : $buildUrl"
            
        Write-Host " > Checking last build's results"
        # Send GET request to Jenkins REST API
        [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $json = (Send-AuthGet -user $JenkinsUser -password $JenkinsPwd -uri "$buildUrl/api/json" -additionalHeaders $additionalHeaders)
        if ($null -eq $json) {
            Write-Error "`$json is NULL on build-job: $($state.Jobs[$i].Name), given build URL: $buildUrl, skipping build-job."
            continue
        }
        [PSCustomObject] $buildInfo = ConvertFrom-Json $json
        $buildInfoStorage.Add($state.Jobs[$i].Name, $buildInfo)

        if ($state.Jobs[$i].Name -eq $upstreamJob.Name) {
            $state.Jobs[$i].Finished = $true
            Write-Host " # Job has finished "
            Write-Host " # Status : $($buildInfo.result) "
            Write-Host " > Checking rules"
            foreach ($team in $Teams) {
                [pscustomobject] $teamSettings = $SETTINGS."$team"
                if ($teamSettings.jobConfig) {
                    try {
                        [bool] $jobInRule = $false
                        foreach ($rule in $teamSettings.jobConfig.rules) {
                            if ($rule.jobs -contains $upstreamJob.Name) {
                                $jobInRule = $true
                                Write-Host " # Job is contained in a rule"
                                if ($rule.notifyOnStatus -contains $buildInfo.result) {
                                    Write-Host " > Sending notifications - $team"
                                    Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $teamSettings.webhookUrl -BuildInfo $buildInfo -Team $team
                                    break
                                }
                            }
                        }
                        
                        if (-not $jobInRule) {
                            Write-Host " # Job is not contained in any rule"
                            Write-Host " > Sending notifications - $team"
                            Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $teamSettings.webhookUrl -BuildInfo $buildInfo -Team $team
                        }
                    }
                    catch {
                        throw $_.Exception.Message
                    }
                }
                else {
                    Write-Host " > Sending notifications - $team"
                    Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $teamSettings.webhookUrl -BuildInfo $buildInfo -Team $team
                }
            }
        }
        # Check if build is not running/in progress
        # If not running check if job is in queue
        elseif ($null -ne $buildInfo.result) {
            Write-Host " # Job has not finished `n > Checking if job is in queue"
            [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $json = (Send-AuthGet -user $JenkinsUser -password $JenkinsPwd -uri "$jobUrl/api/json" -additionalHeaders $additionalHeaders)
            if ($null -eq $json) {
                Write-Error "`$json is NULL on job: $($state.Jobs[$i].Name), given job URL: $jobUrl, skipping job."
                continue
            }
            [PSCustomObject] $jobInfo = ConvertFrom-Json $json
                
            $running[$i] = $jobInfo.inQueue

            Write-Host " # Job is $($jobInfo.inQueue ? '' : 'not ')in queue"
        }
        else {
            # $buildInfo.result -eq $null -- if a build in in progress $buildInfo.result will be null
            $running[$i] = $true
            Write-Host " # Job has not finished `n # Job is in progress "
        }
    }
    Write-Host ""
}

if (($state.Jobs.Finished -contains $false) -and ($running -notcontains $true)) {
    [int] $itt = 0
    [int] $maxItt = 5
    [int] $timeoutSec = 10
    Write-Host "`n[TIMEOUT] No jobs are in queue, sleeping for $timeoutSec seconds before checking again`n"
    Start-Sleep -Seconds $timeoutSec
    while (($running -notcontains $true) -and ($itt -lt $maxItt)) {
        Write-Host "##### Checking for running jobs - Itteration $itt #####"
        for ($i = 0; $i -lt $state.Jobs.Count; $i++) {
            Write-Host "Job $i : "
            Write-Host " - Name      : $($state.Jobs[$i].Name)"
            Write-Host " - Finished  : $($state.Jobs[$i].Finished)"

            if (-not $state.Jobs[$i].Finished) {
                [string] $jobUrl = "$JENKINS_ROOT_URL/job/$($state.Jobs[$i].Name)"
                [string] $buildUrl = "$jobUrl/lastBuild"
                Write-Host " - Job URL   : $jobUrl"
                Write-Host " - build URL : $buildUrl"

                Write-Host " > Checking last build's results"
                [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $json = (Send-AuthGet -user $JenkinsUser -password $JenkinsPwd -uri "$buildUrl/api/json" -additionalHeaders $additionalHeaders)
                if ($null -eq $json) {
                    Write-Error "`$json is NULL on build-job: $($state.Jobs[$i].Name), given build URL: $buildUrl, skipping build-job."
                    continue
                }
                [PSCustomObject] $jobInfo = ConvertFrom-Json $json

                if ($null -eq $jobInfo.result) {
                    $running[$i] = $true
                    Write-Host " # Job is $($running[$i] ? '' : 'not ')running"
                    break
                }
                else {
                    Write-Host " > Checking if job is in queue"
                    [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $json = (Send-AuthGet -user $JenkinsUser -password $JenkinsPwd -uri "$jobUrl/api/json" -additionalHeaders $additionalHeaders)
                    if ($null -eq $json) {
                        Write-Error "`$json is NULL on job: $($state.Jobs[$i].Name), given job URL: $jobUrl, skipping job."
                        continue
                    }
                    [PSCustomObject] $jobInfo = ConvertFrom-Json $json
                    $running[$i] = $jobInfo.inQueue
                    Write-Host " # Job is $($jobInfo.inQueue ? '' : 'not ')in queue"
                    if ($jobInfo.inQueue) { break }
                }
            }
        }
        Write-Host "####################################################`n"
        $itt++
        if ($itt -ne $maxItt) {
            Write-Host ""
            Write-Host "`n[TIMEOUT] No jobs are in queue, sleeping for $timeoutSec seconds`n"
            Start-Sleep -Seconds $timeoutSec
        }
    }
}

[PSCustomObject] $runningState = [ordered]@{}
for ($i = 0; $i -lt $state.Jobs.Count; $i++) {
    $runningState.Add($state.Jobs[$i].Name, $running[$i])
}

Write-Host "##### Running state #####"
$runningState | Format-Table -AutoSize -Wrap @{ Label = "Name"; Expression = { $_.Name }; }, @{ Label = "Running"; Expression = { $_.Value }; }
Write-Host "########################"
Write-Host ""

Write-Host "##### Ending state #####"
$state.Jobs | Format-Table -AutoSize -Wrap Name, Finished
Write-Host "########################"
Write-Host ""

# If no jobs are running, send NOT_BUILT notifications for every unfinished built
if ($running -notcontains $true) {
    Write-Host ">> Notifying if jobs have not run ..."
    [bool] $skipNextJob = ($state.Jobs[0].Finished -ne $true) -and ($state.Jobs.Finished -contains $true)
    for ($i = 0; $i -lt $state.Jobs.Count; $i++) {
        if ($skipNextJob) {
            $skipNextJob = (-not $state.Jobs[$i].Finished)
            if ($skipNextJob) { Write-Host " # [Manual trigger] skipping $($state.Jobs[$i].Name)" }
        }
        if ((-not $state.Jobs[$i].Finished) -and (-not $skipNextJob)) {
            Write-Host " > Checking rules"
            foreach ($team in $Teams) {
                [pscustomobject] $teamSettings = $SETTINGS."$team"
                if ($teamSettings.jobConfig) {
                    try {
                        [bool] $jobInRule = $false
                        foreach ($rule in $teamSettings.jobConfig.rules) {
                            if ($rule.Jobs -contains $state.Jobs[$i].Name) {
                                $jobInRule = $true
                                Write-Host " # Job is contained in a rule"
                                if ($rule.notifyOnStatus -contains "NOT_BUILT") {
                                    Write-Host " > Sending notifications - $team"
                                    Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $teamSettings.webhookUrl -BuildInfo $buildInfoStorage.($state.Jobs[$i].Name) -Team $team -ForceResult "NOT_BUILT"
                                    break
                                }
                            }
                        }
                        
                        if (-not $jobInRule) {
                            Write-Host " # Job is not contained in any rule"
                            Write-Host " > Sending notifications - $team"
                            Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $teamSettings.webhookUrl -BuildInfo $buildInfoStorage.($state.Jobs[$i].Name) -Team $team -ForceResult "NOT_BUILT"
                        }
                    }
                    catch {
                        throw $_.Exception.Message
                    }
                }
                else {
                    Write-Host " > Sending notifications - $team"
                    Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $teamSettings.webhookUrl -BuildInfo $buildInfoStorage.($job.Name) -Team $team -ForceResult "NOT_BUILT"
                }
                Write-Host "-----------------------------------------------`n"
            }
        }
    }

    Write-Host ">> Job sequence ended `n>> Removing state"
    # Clean up the state, as the job-sequence has ended
    Remove-Item -Path $STATE_PATH | Out-Null
}
else {
    Write-Host ">> Job sequence continues `n>> Updating state"
    # Update the state 
    Set-Content -Path $STATE_PATH -Value (ConvertTo-JSON $state) | Out-Null
}

Write-Host ""
Stop-Transcript