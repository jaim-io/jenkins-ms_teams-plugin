# Jenkins MS-Teams Plugin

## Requirements

Powershell Core >= 7.2 has to be installed on the machine that is running the plugin and Jenkins' default route for 'PowerShell' should be set to the PowerShell Core executable (pwsh.exe).

## appsettings.json

`appsettings.json` should follow the format below. You can add however many teams you want.

```json
{
  "parser": {
    "separator": "<SEP>",
    "endOfRow": "<EOR>"
  },
  "<TEAM_NAME>": {
    "webhookUrl": "<MICROSOFT_TEAMS-WEBHOOK_URL>",
    "developers": [
      {
        "id": "<AZURE_AD-ID_OR_UPN>",
        "name": "<NAME>",
        "days": [
          "<ENGLISH_DAYS_MONDAY->SUNDAY>",
          "Monday",
          "Tuesday",
          "Wednesday",
        ]
      },
    ],
    "jobConfig": {
      "rules": [
        {
          "notifyOnStatus": [
            "<BUILT_STATUS>"
          ],
          "jobs": [
            "<JENKINS_JOB_NAME>"
          ]
        },
        {
          "notifyOnStatus": [
            "<BUILT_STATUS>",
            "<BUILT_STATUS>"
          ],
          "jobs": [
            "<JENKINS_JOB_NAME>",
            "<JENKINS_JOB_NAME>"
          ]
        }
      ]
    }
  },
}
```



## Post-Job-Sequence (Main version)

This version monitors a sequence of jobs and is able to notify if one of the jobs had the status `NOT_BUILT`.

### Jenkins configuration

Create a Jenkins job to manage the job sequence. For each sequence of jobs a new manager job should be created and configured. Configure the `Source Code Management` section to clone/pull this repository to the workspace. Under `Build Triggers` check `Build after other projects are built`, check `Always trigger, even if the build is aborted` and add the job names of the job sequence to be watched in `Build after other projects are built`. Then add these job names to the `Description` of the project, each job name should be on a new line. 

Then add a PowerShell build step and copy the following code into it:

```ps1
Set-Location "${env:WORKSPACE}/cmd/post-job-sequence"
./main.ps1 -JenkinsUser "<JENKINS_USER>" -JenkinsPwd "<JENKINS_PASSWORD>" -Teams "<TEAM_NAME>", "<TEAM_NAME>"
```

## Post-Job (Alternative version)

This version monitors a single job and is not able to notify if a job had the status `NOT_BUILT`.

### Running

Create a Jenkins job to manage the standalone job(s). One manager job is able to manage all standalone jobes. Configure the `Source Code Management` section to clone/pull this repository to the workspace. Under `Build Triggers` check `Build after other projects are built`, check `Always trigger, even if the build is aborted` and add the job names of the jobs to be watched in `Build after other projects are built`.

Then add a PowerShell build step and copy the following code into it:

```ps1
Set-Location "${env:WORKSPACE}/cmd/post-job"
./main.ps1 -JenkinsUser "<JENKINS_USER>" -JenkinsPwd "<JENKINS_PASSWORD>" -Teams "<TEAM_NAME>", "<TEAM_NAME>"
```
