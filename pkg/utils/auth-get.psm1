<#
  .DESCRIPTION
  Send a GET request with a Authorization header.

  .EXAMPLE
  Parameters -|
    $user     = "Jack"
    $password = "Daniels"
    $uri = "https://localhost:8080/jenkins/view/My_View/job/My_Job/140/"
  Returns -| 
    [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject]
  #>
function Send-AuthGet (
  [Parameter(Mandatory)] [string]    $user, 
  [Parameter(Mandatory)] [string]    $password, 
  [Parameter(Mandatory)] [string]    $uri,
                         [hashtable] $additionalHeaders
){
  # The header is the username and password concatenated together
  [string] $pair = "$($user):$($password)"
  # The combined credentials are converted to Base 64
  [string] $encodedCreds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
  # The base 64 credentials are then prefixed with "Basic"
  [string] $basicAuthValue = "Basic $encodedCreds"
  # This is passed in the "Authorization" header
  [hashtable] $headers = [hashtable]@{
    "Authorization" = $basicAuthValue
  }
  
  $headers += $null -ne $additionalHeaders ? $additionalHeaders : @{} 

  [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $result = Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing
  return $result
}
  
Export-ModuleMember -Function Send-AuthGet