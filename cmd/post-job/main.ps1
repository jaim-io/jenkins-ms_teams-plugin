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
Write-Host "`nUpstream job :`n    Name   : $($upstreamJob.Name)`n    Number : $($upstreamJob.Number)`n
"

[string] $jobUrl = "$JENKINS_ROOT_URL/job/$($upstreamJob.Name)"
[string] $buildUrl = "$jobUrl/lastBuild"
Write-Host " - Job URL   : $jobUrl"
Write-Host " - build URL : $buildUrl"
Write-Host " > Checking last build's results"

# Send GET request to Jenkins REST API
[Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $json = (Send-AuthGet -user $JenkinsUser -password $JenkinsPwd -uri "$($buildUrl)/api/json" -additionalHeaders $additionalHeaders)
if ($null -eq $json) {
    throw "`$json is NULL on build-job: $($upstreamJob.Name), given build URL: $buildUrl, skipping build-job."
}
[PSCustomObject] $buildInfo = ConvertFrom-Json $json

Write-Host " # Status : $($buildInfo.result) "
foreach ($team in $Teams) {
    [pscustomobject] $teamSettings = $SETTINGS."$team"
    if ($teamSettings.jobConfig) {
        try {
            [bool] $jobInRule = $false
            foreach ($rule in $teamSettings.jobConfig.rules) {
                if ($rule.jobs -contains $upstreamJob.Name) {
                    $jobInRule = $true
                    if ($rule.notifyOnStatus -contains $buildInfo.result) {
                        Write-Host " # Job matching rule"
                        Write-Host " > Sending notifications - $team"
                        Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $teamSettings.webhookUrl -BuildInfo $buildInfo -Team $team
                    }
                }
            }
            
            if (-not $jobInRule) {
                Write-Host " # Job not contained in any rule"
                Write-Host " > Sending notifications - $team"
                Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $teamSettings.webhookUrl -BuildInfo $buildInfo -Team $team
            }
        } catch {
            throw $_.Exception.Message
        }
    } else {
        Write-Host " > Sending notifications - $team"
        Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $teamSettings.webhookUrl -BuildInfo $buildInfo -Team $team
    }
    Write-Host "-----------------------------------------------`n"
}

Stop-Transcript