Import-Module "$PSScriptRoot/../utils/date.psm1"

class Developer {
  [ValidateNotNullOrEmpty()] [string]   $Id
  [ValidateNotNullOrEmpty()] [string]   $Name
  [ValidateNotNull()]        [string[]] $Days
}
   
<#
    .DESCRIPTION
    Get-Developers reads, parses and returns all developer from ./config.json.
  
    .EXAMPLE
    Returns -| 
      [Collections.Generic.List[developer]]@(
        @{
          Id   = "jamey.schaap@sweco.nl"
          Name = "Schaap, Jamey"
          Days = @(
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday" 
          )
        },
        @{
          Id   = "danny.aldering@sweco.nl"
          Name = "Aldering, Danny"
          Days = @(
            "Monday", "Thursday", "Friday" 
          )
        },
      )
  #>
function Get-Developers(
  [Parameter(Mandatory)][string] $team
) {
  if (-not [IO.File]::Exists("$PSScriptRoot/../../appsettings.json")) {
    throw "File appsettings.json does not exist, unable to load team configuration"
  }
  
  [pscustomobject]$settings = (Get-Content -Raw "$PSScriptRoot/../../appsettings.json") | ConvertFrom-Json
  
  [string] $team = $team.ToLower()
  if (-not $settings."$team") { throw "Given team '$team' does not exist in appsettings.json" }
  
  [Collections.Generic.List[developer]] $developers = [Collections.Generic.List[developer]]::new()
  foreach ($dev in $settings."$team".developers) {
    $developers.Add([developer]$dev)
  }

  return ($developers ? $developers : ([Collections.Generic.List[developer]]::new()))
}
    
<#
    .DESCRIPTION
    Get-DevelopersByDate gets developers that are assigned to a certain day.
  
    .EXAMPLE
    Parameter -|
      $date = "Monday, 31-10-2022 10:28:36"
    Returns -| 
      [Collections.Generic.List[developer]]@(
        @{
          Id   = "jamey.schaap@sweco.nl"
          Name = "Schaap, Jamey"
          Days = @(
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday" 
          )
        },
        @{
          Id   = "danny.aldering@sweco.nl"
          Name = "Aldering, Danny"
          Days = @(
            "Monday", "Thursday", "Friday" 
          )
        },
      )
  #>
function Get-DevelopersByDate(
  [Parameter(Mandatory)] [string]$date,
  [Parameter(Mandatory)] [developer[]]$developers
) {
  [Collections.Generic.List[developer]] $result = [Collections.Generic.List[developer]]::new()
        
  foreach ($day in (Get-Weekdays).GetEnumerator()) {
    if ($date.Contains($day.Key) -or $date.Contains($day.Value)) {
      foreach ($dev in $developers) {
        if ($dev.Days.Contains($day.Key) -or $dev.Days.Contains($day.Value)) {
          $result.Add($dev)
        }
      }
    }
  }
              
  if ($result.Count -eq 0) {
    Write-Host "  
#### GetDeveloperByDate ####
Date should contain a week day Monday-Sunday. 
If this was intentional, this message can be ignored. 
No developer is assigned to this day. Date: $date
######################"
  }

  return $result
}

Export-ModuleMember -Function Get-Developers
Export-ModuleMember -Function Get-DevelopersByDate