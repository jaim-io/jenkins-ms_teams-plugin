#Requires -Version 7.0
#Requires -PSEdition Core

param(
  [Parameter(Mandatory)] [string]           $JenkinsUser,
  [Parameter(Mandatory)] [string]           $JenkinsPwd,
  [Parameter(Mandatory)] [string]           $WebhookUrl,
  [Parameter(Mandatory)] [string]           $BuildUrl,
  [Parameter(Mandatory)] [string]           $Team,
                         [pscustomobject]   $BuildInfo,
                         [string]           $ForceResult
)

Import-Module "$PSScriptRoot/notify.psm1"

Notify $JenkinsUser $JenkinsPwd $WebhookUrl $BuildUrl $Team $BuildInfo $ForceResult