enum Status {
  Success
  Failure
  Unstable
  Not_Built
  Aborted
  In_Progress
}

class Build {
  [ValidateNotNullOrEmpty()][string]$JobName
  [ValidateNotNullOrEmpty()][string]$Number
  [ValidateNotNullOrEmpty()][status]$Status
  [ValidateNotNullOrEmpty()][string]$Start
  [ValidateNotNullOrEmpty()][string]$End
  [string]$EstEnd
  [ValidateNotNullOrEmpty()][string]$Duration
  [string]$EstDuration
  [ValidateNotNullOrEmpty()][string]$URL
}

class UpstreamJob {
  [string] $Name
  [int32] $Number

  UpstreamJob ([string] $name,[int32] $number) {
    $this.Name = $name
    $this.Number = $number
  }
}

function Get-UpstreamJob([pscustomobject] $buildInfo) {
  foreach ($action in $buildInfo.actions) {
    if ($action._class -eq "hudson.model.CauseAction") {
      foreach ($cause in $action.causes) {
        if ($cause._class -eq "hudson.model.Cause`$UpstreamCause") {
          return [UpstreamJob]::new($cause.upstreamProject, $cause.upstreamBuild)
        }
      }
    }
  }
  
  return $null
}

class Job {
  [string]   $Name
  [bool]     $Finished
  [int]      $SequenceNumber
}

Export-ModuleMember -Function Get-UpstreamJob