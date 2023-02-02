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

if ($PSVersionTable.PSEdition -eq "Core" -and $PSVersionTable.PSVersion.Major -eq 7) {
    ./main.ps1 -JenkinsUser $JenkinsUser -JenkinsPwd $JenkinsPwd -JenkinsRootUrl $JenkinsRootUrl -MSTeamsWebhookUrl $MSTeamsWebhookUrl -Jobs $Jobs
}
else {
    throw "Powershell version not high enough. Requires minimally: Powershell Core 7. Current version is: Powershell $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion.Major)."
}