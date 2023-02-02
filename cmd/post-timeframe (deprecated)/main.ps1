#Requires -Version 7.0
#Requires -PSEdition Core

param(      
    [Parameter(Mandatory)] 
    [Alias("ju", "user")]                                                                    
    [string] $JenkinsUser,

    [Parameter(Mandatory)] 
    [Alias("jp", "pwd")]                                                                     
    [string] $JenkinsPwd,

    [Parameter(Mandatory)] 
    [Alias("jru", "RootUrl")]
    [string] $JenkinsRootUrl,

    [Parameter(Mandatory)] 
    [Alias("mtwu", "Webhook", "WebhookUrl")]
    [string] $MSTeamsWebhookUrl,

    [Parameter(Mandatory)] 
    [Alias("j")] 
    [ValidateScript({ $_.Length -ge 1 })]
    [string[]] $Jobs
)

begin {
    if (-not (Test-Path -Path ../../logs)) {
        try {
            New-Item -ItemType Directory -Path ../../ -Name logs -ErrorAction Stop
        }
        catch {
            throw $_.Exception.Message
        }
    }
    Start-Transcript -Path "../../logs/events_$((Get-Date).ToString("dd-MM-yyyy_HH-mm-ss")).log"

    Import-Module "../../pkg/jenkins-msteams/notify.psm1"
    Import-Module "../../pkg/utils/auth-get.psm1"
    
    [datetime] $timeframeStart = $timeframeEnd = Get-Date
}
process {
    for ($i = 0; $i -lt $Jobs.Length; $i++) {
        # Trim / from the end of the URL to prevent // issues.
        [string] $buildUrl = "$($JenkinsRootUrl.TrimEnd("/").TrimEnd("\"))/job/$($Jobs[$i])/lastBuild"
        
        # Configure request headers
        [hashtable] $additionalHeaders = @{
            "Cache-Control" = "no-cache"
        }
    
        # Send GET request to Jenkins REST API
        [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $result = (Send-AuthGet -user $JenkinsUser -password $JenkinsPwd -uri "$($buildUrl)/api/json" -additionalHeaders $additionalHeaders)
        if ($null -eq $result) {
            if ($i -eq 0) {
                throw "`$result is NULL, unable to determine the start of the timeframe. The start of the timeframe is required to determine if a job ran within the timeframe."
            } 
            Write-Error "`$result is NULL on jobs: $($Jobs[$i]), given URL: $buildUrl, skipping entry."
            continue
        }
        [PSCustomObject] $buildInfo = ConvertFrom-Json $result
    
        # Jenkins returns CET - 1 hours, therefore we add 1 hour
        [datetime] $buildEnd = [datetimeoffset]::FromUnixTimeMilliseconds($buildInfo.timestamp).DateTime.AddHours(1)
        if ($i -eq 0) {
            $timeframeStart = $buildEnd - ([TimeSpan]::FromMilliseconds($buildInfo.duration))
        }
        [boolean] $builtWithinTimeframe = ($timeframeStart -le $buildEnd) -and ($buildEnd -le $TimeframeEnd)

        if ($builtWithinTimeframe) {
            switch ($buildInfo.result) {
                "SUCCESS" {
                    break
                }
                $null {
                    Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $MSTeamsWebhookUrl -ForceResult "IN_PROGRESS"
                }
                default {
                    Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $MSTeamsWebhookUrl -BuildInfo $buildInfo
                }
            }
        }
        else {
            Notify -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -BuildUrl $buildUrl -WebhookUrl $MSTeamsWebhookUrl -ForceResult "NOT_BUILT"
        }
    }
    
    Stop-Transcript
}