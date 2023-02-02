############# Imports all used module-functions #############
############## into the current Shell sessionn ##############
Import-Module "$PSScriptRoot/../utils/date.psm1"
Import-Module "$PSScriptRoot/../utils/auth-get.psm1"
Import-Module "$PSScriptRoot/developer.psm1"
Import-Module "$PSScriptRoot/jenkins.psm1"
Import-Module "$PSScriptRoot/ms-teams.psm1"

########## Imports the Developer and Build classes ##########
###### And Status enum into the current Shell sessionn ######
[string] $jenkinsModule = "$PSScriptRoot/jenkins.psm1"
[string] $developerModule = "$PSScriptRoot/developer.psm1"
[string] $scriptBody = "
  Using module $jenkinsModule
  Using module $developerModule
  "
[ScriptBlock] $script = [ScriptBlock]::Create($scriptBody)
. $script
#############################################################


function Notify(
    [Parameter(Mandatory)] [string]         $jenkinsUser,
    [Parameter(Mandatory)] [string]         $jenkinsPwd,
    [Parameter(Mandatory)] [string]         $webhookUrl,
    [Parameter(Mandatory)] [string]         $buildUrl,
    [Parameter(Mandatory)] [string]         $Team,
                           [pscustomobject] $buildInfo = (ConvertFrom-Json (Send-AuthGet $jenkinsUser $jenkinsPwd "$buildUrl/api/json")),
    [ValidateSet("SUCCESS", "FAILURE", "UNSTABLE", "NOT_BUILT", "ABORTED", "IN_PROGRESS", IgnoreCase = $true)] 
                           [string]         $forceResult
) {
    Write-Host "    1: Configuring ........
    "

    $result = if ($forceResult) {
                ($forceResult.ToUpper())
              } else {
                $buildInfo.result
              }

    [string] $color | Out-Null
    [string] $status | Out-Null
    switch ( $result) {
        "SUCCESS" {
            $color = "good"
            $status = [Status]::Success
        }
        "FAILURE" {
            $color = "attention"
            $status = [Status]::Failure
        }
        "UNSTABLE" {
            $color = "warning"
            $status = [Status]::Unstable 
        }
        "NOT_BUILT" {
            $color = "warning"
            $status = [Status]::Not_Built
        }
        "ABORTED" {
            $color = "accent"
            $status = [Status]::Aborted
        }
        "IN_PROGRESS" {
            $color = "accent"
            $status = [Status]::In_Progress 
        }
        $null {
            $color = "accent"
            $status = [Status]::In_Progress 
        }
        default { 
            throw "Invalid build result."
        }
    }

    [timespan] $durationTS = [TimeSpan]::FromMilliseconds($buildInfo.duration)
    [string] $duration = switch ($durationTS) {
  
        { $PSItem -gt ( New-TimeSpan -Days 1) } {
            $durationTS.ToString("dd' days 'hh' hours 'mm' minutes 'ss' seconds'")
        }
        { $PSItem -lt ( New-TimeSpan -Minutes 1) } {
            $durationTS.ToString("mm' minutes 'ss' seconds 'fff' milliseconds'")
        }
        default {
            $durationTS.ToString("hh' hours 'mm' minutes 'ss' seconds'")
        }
    }

    # Jenkins REST API Time is 1 hour behind
    [datetime] $buildEndDT = [datetimeoffset]::FromUnixTimeMilliseconds($buildInfo.timestamp).DateTime.AddHours(1)
    [string] $buildEndDutch = $buildEndDT.ToString("dddd, dd/MM/yyyy HH:mm:ss")
    [string] $buildEnd = Rename-DayToEnglish $buildEndDutch


    [datetime] $buildStartDT = $buildEndDT - $durationTS
    [string] $buildStartDutch = $buildStartDT.ToString("dddd, dd/MM/yyyy HH:mm:ss")
    [string] $buildStart = Rename-DayToEnglish $buildStartDutch

    [string] $today = Rename-DayToEnglish ((Get-Date).ToString("dddd, dd/MM/yyyy HH:mm:ss"))
    [Collections.Generic.List[developer]] $developers = Get-Developers $Team
    if ($developers) {
        [Collections.Generic.List[developer]] $developers = Get-DevelopersByDate $today $developers
    } else {
        [Collections.Generic.List[developer]] $developers = [Collections.Generic.List[developer]]::new()
    }
    [build] $build = [build]@{ 
        # Trims buildnumber (#\d+) from the full name and then trims leading and trailing whitespace
        # Example `XX._Obsurv_-_Job_Tracker_test #29` -> `XX._Obsurv_-_Job_Tracker_test`
        # Leading and trailing whitespace causes the Markdown/HTML styling, like bold/italic/etc to break.
        JobName      = ($buildInfo.fullDisplayName).Substring(0, ($buildInfo.fullDisplayName).Length - ($buildInfo.displayName).Length ).Trim()
        Number       = $buildInfo.number
        Status       = $status
        Start        = $buildStart
        End          = $buildEnd
        Duration     = $duration
        URL          = $buildInfo.url
    }

    if ($build.Status -eq [Status]::In_Progress) {
        [timespan] $estDurationTS = [TimeSpan]::FromMilliseconds($buildInfo.estimatedDuration)
        [string] $estDuration = switch ($durationTS) {
      
            { $PSItem -gt ( New-TimeSpan -Days 1) } {
                $estDurationTS.ToString("dd' days 'hh' hours 'mm' minutes 'ss' seconds'")
            }
            { $PSItem -lt ( New-TimeSpan -Minutes 1) } {
                $estDurationTS.ToString("mm' minutes 'ss' seconds 'fff' milliseconds'")
            }
            default {
                $estDurationTS.ToString("hh' hours 'mm' minutes 'ss' seconds'")
            }
        }


        [datetime] $estBuildEndDT = $buildStartDT + $estDurationTS
        [string] $estBuildEndDutch = $estBuildEndDT.ToString("dddd, dd/MM/yyyy HH:mm:ss")
        [string] $estBuildEnd = Rename-DayToEnglish $estBuildEndDutch

        $build.EstDuration  = $estDuration
        $build.EstEnd = $estBuildEnd
    }

    [uint16] $indentRight = switch($build.Status) {
        ([Status]::In_Progress) { 3 }
        default { 5 }
    }
  
    Write-Host "    ################ Configuration ################
    Status:         $($build.Status)
    Color:          $color
    Assignees:      $(if ($developers.Name.Count -gt 0) { $developers.Name -join " - " } else { "Noone was assigned" })
    Job name:       $($build.JobName)
    Build number:   $($build.Number)
    Build URL:      $($build.URL)
    Start date:     $($build.Start)
    End date:       $($build.End)
    Duration:       $($build.Duration)
    ###############################################
    "
    Write-Host "    1: [DONE]
    "  
    Write-Host "    2: Creating request body ........"
    [PSCustomObject] $jsonBody = New-MSTeamsRequestBody $color $indentRight $build $developers
    [string] $requestBody = ConvertTo-Json $jsonBody -Depth 100
    Write-Host "    2: [DONE]
    "

    Write-Host "    3: Sending POST request ........"
    $response = Send-MSTeamsMessage $requestBody $webhookUrl

    # The status code MS-Teams returns may differ from the request statuscode.
    # This indicates if the MS-Teams request has successfully been posted.
    # Although StatusCode may show 200, the first rule in RawContent maybe return 4xx.
    ($response.RawContent -match "HTTP/\d\.\d\s\d\d\d\s\w+") | Out-Null
    Write-Host "    ################### Response ##################
    RequestStatusCode : $($response.StatusCode)
    StatusDescription : $($response.StatusDescription)
    Content           : $($response.Content)
    MSTeamsStatusCode : $($Matches[0])
    ###############################################
    "

    Write-Host "    3: [DONE]"
}

Export-ModuleMember -Function Notify