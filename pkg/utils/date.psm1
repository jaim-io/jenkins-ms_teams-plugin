# Weekdays Dutch -> English
function Get-Weekdays() {
  return @{
    "maandag"   = "Monday";
    "dinsdag"   = "Tuesday";
    "woensdag"  = "Wednesday";
    "donderdag" = "Thursday";
    "vrijdag"   = "Friday";
    "zaterdag"  = "Saturday";
    "zondag"    = "Sunday";
  }
}
      
<#
    .DESCRIPTION
    TranslateDayToEnglish translates a weekday in Dutch to English
  
    .EXAMPLE
    Parameter -|
      $text = "Maandag, 31-10-2022 10:28:36"
    Returns -| 
      "Monday, 31-10-2022 10:28:36"
  #>
function Rename-DayToEnglish (
  [Parameter(Mandatory)] [string]$text
) {
  foreach ($day in (Get-Weekdays).GetEnumerator()) {
    [string] $lowerText = $text.ToLower()
    # maandag / MAANDAG -> Monday
    if ($lowerText.Contains($day.Key)) { 
      return $lowerText.Replace($day.Key, $day.Value)
    }
    # monday / MONDAY -> Monday
    elseif ($lowerText.Contains($day.Value.ToLower())) {
      return $lowerText.Replace($day.Value.ToLower(), $day.Value)
    }
  }
      
  return $text
}

Export-ModuleMember -Function Get-Weekdays
Export-ModuleMember -Function Rename-DayToEnglish