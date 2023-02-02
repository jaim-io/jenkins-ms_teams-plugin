#Requires -Version 7.0
#Requires -PSEdition Core

param(
	[Parameter(Mandatory)][string] $JenkinsUser,
	[Parameter(Mandatory)][string] $JenkinsPwd,
	[Parameter(Mandatory)][string] $JenkinsViewUrl,
	[Parameter(Mandatory)][string] $WebhookUrl,
	# Format dd.HH:MM:SS.ss
	# Days and Miliseconds are optional -> HH:MM:SS
	[Parameter(Mandatory)][ValidatePattern("\d*\.?\d+\:\d+:\d+\.?\d*")][string] $TimoutDuration,
	[Parameter(Mandatory)][ValidatePattern("\d*\.?\d+\:\d+:\d+\.?\d*")][string] $MaxDuration,
	# Jenkins jobs within the view to be ignored
	[string[]] $Ignore,
	# Continue until all jobs are finished if $MaxDuration has been exceeded
	[switch]$Continue = $false
)

class Job {
	[string]   $Name
	[datetime] $LastSuccess
	[datetime] $LastFailure 
	[bool]     $Finished
}

function Initialize-Jobs {
	param(
		[ref][Collections.Generic.List[job]] $jobsPtr,
		[string[]] $jobRows
	)
	
	foreach ($row in $jobRows) {
		[string] $name, $recentSuccess, $recentFail = $row -split $settings.parser.separator
		$name = $name.SubString(4)

		if ($Ignore -contains $name) {
			continue
		}

		$jobsPtr.Value.Add(
			[job]@{
				# Removes job_ from the name
				Name        = $name
				LastSuccess = if (-not ([string]::IsNullOrEmpty($recentSuccess))) { [datetime] $recentSuccess } else { $defaultDT }
				LastFailure = if (-not ([string]::IsNullOrEmpty($recentFail))) { [datetime] $recentFail } else { $defaultDT }
				Finished    = $false
			}
		)
	}
}

function Update-Jobs {
	param(
		[ref][Collections.Generic.List[job]] $jobsPtr,
		[string[]] $jobRows
	)
	
	foreach ($row in $jobRows) {
		[string] $name, $recentSuccess, $recentFail = $row -split $settings.parser.separator
		# Removes job_ from the name
		$name = $name.SubString(4)
		$lastSuccess = if (-not ([string]::IsNullOrEmpty($recentSuccess))) { [datetime] $recentSuccess } else { $defaultDT }
		$lastFailure = if (-not ([string]::IsNullOrEmpty($recentFail))) { [datetime] $recentFail } else { $defaultDT }

		for ($i = 0; $i -lt $jobsPtr.Value.Count; $i++) {
			$jobsRef = $jobsPtr.Value

			if ($Ignore -contains $name) {
				continue
			}

			if ($jobsRef[$i].Name -eq $name) {
				if (($jobsRef[$i].LastSuccess -ne $lastSuccess) -or ($jobsRef[$i].LastFailure -ne $lastFailure)) {
					$jobsRef[$i].Finished = $true

					if ($jobsRef[$i].LastSuccess -ne $defaultDT -and [string]::IsNullOrEmpty($recentSuccess)) {
						Write-Host ""
						Write-Host "$name : LAST SUCCESS LOGS FLUSHED"
						Write-Host "> Setting Last Failure to default ....."
					}
					elseif ($jobsRef[$i].LastFailure -ne $defaultDT -and [string]::IsNullOrEmpty($recentFail)) {
						Write-Host ""
						Write-Host "$name : LAST FAILURE LOGS FLUSHED"
						Write-Host "> Setting Last Failure to default ......"
					}
					elseif ($jobsRef[$i].LastFailure -ne $lastFailure) {
						# Call the jenkins-msteams module to send a msteams notifications
						$sep = if (($JenkinsViewUrl[-1] -eq "/") -or ($JenkinsViewUrl[-1] -eq "\")) { "" } else { "/" }
						$buildUrl = $JenkinsViewUrl + $sep + "job/$name/lastBuild"
						
						Write-Host "$name : BUILD FAILED"
						Write-Host "Sending Notification .....
						"
						Notify -jenkinsUser $JenkinsUser -jenkinsPwd $JenkinsPwd -buildUrl $buildUrl -WebhookUrl $WebhookUrl
					}

					$jobsRef[$i].LastSuccess = if (-not ([string]::IsNullOrEmpty($recentSuccess))) { [datetime] $recentSuccess } else { $defaultDT }
					$jobsRef[$i].LastFailure = if (-not ([string]::IsNullOrEmpty($recentFail))) { [datetime] $recentFail } else { $defaultDT }
				}
			}
		}
	}
}

############ MAIN BODY ############
if (-not (Test-Path -Path ../../logs)) {
	try {
		New-Item -ItemType Directory -Path ../../ -Name logs -ErrorAction Stop
	}
	catch {
		throw $_.Exception.Message
	}
}
Start-Transcript -Path "../../logs/events_$((Get-Date).ToString("dd-MM-yyyy_HH-mm-ss")).log"

# Configure application settings
[pscustomobject] $settings = (Get-Content -Raw ../../appsettings.json | ConvertFrom-Json)

# Install npm dependencies - JSDOM
Push-Location "../../pkg/html-parser"
(npm install) | Out-Null
Pop-Location

# Import modules
Import-Module "../../pkg/jenkins-msteams/notify.psm1"
Import-Module "../../pkg/utils/auth-get.psm1"

[datetime] $start = Get-Date
[datetime] $end = $start.Add([timespan]$MaxDuration)

[boolean] $initial = $true
[datetime] $defaultDT = [datetime]"1/1/0001"

[Collections.Generic.List[job]] $jobs = [Collections.Generic.List[job]]::new()
[int16] $run = 1
[boolean] $running = $true

# Powershell Lambda
$ConfirmJobsFinished = { param([Collections.Generic.List[job]] $arr) $arr.Finished -notcontains $false }
[boolean] $finished = $false

do {
	Write-Host "
############### Run $run - $(Get-Date) ###############
"
	# Get the HTML of the given View
	$html = (Send-AuthGet $JenkinsUser $JenkinsPwd $JenkinsViewUrl).ToString()

	try {
		New-Item -Path ../../ -Name "temp" -ItemType "file" -Value $html -Force -ErrorAction Stop | Out-Null
	}
	catch {
		throw $_.Exception.Message
	}
	$result = $(node ../../pkg/html-parser/main.js)
	Remove-Item "../../temp" | Out-Null
	
	# Debug information in logs - Raw data
	Write-Host -InformationAction Ignore
	Write-Host "$result" -InformationAction Ignore
	Write-Host -InformationAction Ignore

	[string[]] $jobRows = $result -split $settings.parser.endOfRow
	
	if ($initial) {
		Write-Host "Initializing Jobs ....."
		Initialize-Jobs ([ref]$jobs) $jobRows
		$initial = $false
	}
	else {
		Write-Host "Updating Jobs ....."
		Update-Jobs ([ref]$jobs) $jobRows
	}

	Write-Host "
__________________________ State __________________________"

	$jobs | Format-Table -AutoSize -Wrap Name, @{ Label = "Last Success"; Expression = { $_.LastSuccess }; Width = 100 }, @{ Label = "Last Failure"; Expression = { $_.LastFailure } }, @{ Label = "Finished"; Expression = { $_.Finished } }
	$finished = (&$ConfirmJobsFinished $jobs)
	if ($finished) {
		break
	}
	$run++
	
	$dtAfterTimeout = (Get-Date).Add([timespan]$TimoutDuration)
	$running = (($dtAfterTimeout -lt $end) -and -not $finished) -or (($dtAfterTimeout -ge $end) -and -not $finished -and $Continue)
	if ($running) {
		# Timout period
		Write-Host "             dd_hh_mm_ss_fff"
		Write-Host "Sleeping for $TimoutDuration"
		Write-Host "..........................................................."
		Start-Sleep -Seconds $([timespan]$TimoutDuration).TotalSeconds
	}

} while ($running) 

if (-not $finished) {
	Write-Host "
	################ Checking unfinished jobs #################
	"
	foreach ($job in $jobs) {
		if (-not $job.Finished) {
			$sep = if (($JenkinsViewUrl[-1] -eq "/") -or ($JenkinsViewUrl[-1] -eq "\")) { "" } else { "/" }
			$buildUrl = $JenkinsViewUrl + $sep + "job/$($job.Name)/lastBuild/api/json"
	
			$buildInfo = ConvertFrom-Json (Get-JenkinsData $JenkinsUser $JenkinsPwd $buildUrl)
	 
			if ($null -eq $buildInfo.result) {
				Write-Host "$($job.Name) : IN Progress"
				Write-Host "Sending Notification .....
				"
				Notify -jenkinsUser $JenkinsUser -jenkinsPwd $JenkinsPwd -buildUrl $buildUrl -WebhookUrl $WebhookUrl -buildInfo $buildInfo
			}
			else {
				Write-Host "$($job.Name) : NOT BUILT"
				Write-Host "Sending Notification .....
				"
				Notify -jenkinsUser $JenkinsUser -jenkinsPwd $JenkinsPwd -buildUrl $buildUrl -WebhookUrl $WebhookUrl -forceResult "NOT_BUILT"
			}
			Write-Host "___________________________________________________________"
		}
	}
}
else {
	Write-Host "################# All jobs are finished ###################"
}

Write-Host "
########################## DONE ###########################
"

Stop-Transcript