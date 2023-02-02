########## Imports the Developer and Build classes ##########
[string] $developerModule = "$PSScriptRoot\developer.psm1"
[string] $jenkinsModule = "$PSScriptRoot\jenkins.psm1"
[string] $scriptBody = "
  Using module $developerModule
  Using module $jenkinsModule
  "
[ScriptBlock] $script = [ScriptBlock]::Create($scriptBody)
. $script
#############################################################

class MSTeamsEntities {
  [string] $Text
  [Collections.Generic.List[PSCustomObject]] $Entities
}

<#
    .DESCRIPTION
    New-MSTeamsEntities creates mention sections for all given developers and a string matching the all 'text' fields.
  
    .EXAMPLE
    Parameters -|
      $developers = [Collections.Generic.List[developer]]@(
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
      }
    Returns -| 
      1: A List containing all the 'mention' MS-Teams section containing each given developer. 
      2: Text containing a joined string of the 'text' property of the 'mention' section.
      [string] $Text = "<at>Schaap, Jamey UPN</at>, <at>Alderding, Danny UPN</at>"
      [Collections.Generic.List[PSCustomObject]] $Entities = []@(
        @{
          "type"      = "mention"
          "text"      = $mentionText
          "mentioned" = @{
            "id"   = $developers[$i].Id
            "name" = $developers[$i].Name
          }
        },
        @{
          "type"      = "mention"
          "text"      = $mentionText
          "mentioned" = @{
            "id"   = $developers[$i].Id
            "name" = $developers[$i].Name
          }
        }
      )
  #>
function New-MSTeamsEntities (
  [Collections.Generic.List[developer]] $developers = [Collections.Generic.List[developer]]::new()
) {
  [string] $assigneesText
  [Collections.Generic.List[PSCustomObject]] $msTeamsEntities = [Collections.Generic.List[PSCustomObject]]::new()
  if ($developers.Count -ne 0) {
    for ($i = 0; $i -lt $developers.Count; $i++) {
      [string] $mentionText = "<at>$($developers[$i].Name) UPN</at>"
      [string] $separator = switch ($i) {
        { $PSItem + 1 -eq $developers.Count - 1 } {
          " and "
        }
        { $PSItem + 1 -eq $developers.Count } {
          ""
        }
        default {
          ", "
        }
      }
      
      $assigneesText += ($mentionText + $separator)
      $msTeamsEntities.Add(
        [PSCustomObject]@{
          "type"      = "mention"
          "text"      = $mentionText
          "mentioned" = @{
            "id"   = $developers[$i].Id
            "name" = $developers[$i].Name
          }
        })
    }
  }
  else {
    $assigneesText = "Noone is assigned"
  }
  
  return [MSTeamsEntities]@{
    Entities = $msTeamsEntities 
    Text     = $assigneesText
  }
}

<#
    .DESCRIPTION
    New-MSTeamsRequestBody returns the MS-Teams request body as [PSCustomObject] in a JSON-like structure.
  
    .EXAMPLE
    Parameters -|
      $color        = "attention"
      $indentRight  = 5
      $developer    = [developer]@{
        Name = "Schaap, Jamey"
        Id = "jamey.schaap@sweco.nl"
        Days = @(
          "Monday"
        )
      }
      $build    = [build]@{
        JobName   = "Create from trunk" 
        Number    = "123"
        Status    = "Failure"
        StartDate = "Monday, 01/11/2022 12:11:42"
        EndDate   = "Tuesday, 01/11/2022 12:11:44"
        Duration  = "00:00:02.8407316"
        URL       = "https://localhost:8080/jenkins/view/My_View/job/My_Job/140/"
      }
    Returns -| 
      A PSCustomObject object in a JSON-like structure.
  #>
function New-MSTeamsRequestBody(
  [Parameter(Mandatory)] [string]                                     $color,
  [Parameter(Mandatory)] [uint16]                                     $indentRight,
  [Parameter(Mandatory)] [build]                                      $build,
                         [Collections.Generic.List[developer]] $developers = [Collections.Generic.List[developer]]::new()
) {
  $msTeams = New-MSTeamsEntities $developers
        
  [string] $asigneesText = $msTeams.Text
          
  # Weird behaviour
  # List from function result ($msTeams.Entities) gets destructed if $msTeams.Entities.Count = 1
  [Collections.Generic.List[PSCustomObject]] $msTeamsEntities = [Collections.Generic.List[PSCustomObject]]::new()
  foreach ($en in $msTeams.Entities) {
    $msTeamsEntities.Add($en)
  }
        
  [PSCustomObject] $body = [PSCustomObject][Ordered]@{
    "type"        = "message"
    "attachments" = @(
      @{
        "contentType" = "application/vnd.microsoft.card.adaptive"
        "content"     = @{
          "type"     = "AdaptiveCard"
          "body"     = [Collections.Generic.List[PSCustomObject]]@(
            @{
              "type"   = "TextBlock"
              "size"   = "Medium"
              "weight" = "Bolder"
              "text"   = "**$($build.JobName)**"
              "color"  = $color
            },
            @{
              "type"    = "ColumnSet"
              "columns" = @(
                @{
                  "type"  = "Column"
                  "width" = 1
                  "items" = @(
                    @{
                      "type"   = "TextBlock"
                      "weight" = "Bolder"
                      "text"   = "**Status**"
                    }
                  )
                },
                @{
                  "type"  = "Column"
                  "width" = $indentRight
                  "items" = @(
                    @{
                      "type"  = "TextBlock"
                      "text"  = ("$($build.Status)" -replace "_", " ")
                      "color" = $color
                    }
                  )
                }
              )
            }
          )
          "`$schema" = "http://adaptivecards.io/schemas/adaptive-card.json"
          "version"  = "1.0"
          "msteams"  = @{
            "entities" = [Collections.Generic.List[PSCustomObject]]::new()
          }
        }
      }
    )
  }

  if ($build.Status -ne [Status]::Not_Built) {
    $body.attachments.content.actions = @(
      @{
        "type"  = "Action.OpenUrl"
        "title" = "View Build"
        "url"   = "$($build.URL)"
      }
    )
    $body.attachments.content.body.Insert(1, @{
        "type"     = "TextBlock"
        "spacing"  = "none"
        "text"     = "Latest build $($build.Number)"
        "isSubtle" = "true"
      })

    $body.attachments.content.body.AddRange(
      [Collections.Generic.List[PSCustomObject]]@(   
        @{
          "type"    = "ColumnSet"
          "spacing" = "none"
          "columns" = @(
            @{
              "type"  = "Column"
              "width" = 1
              "items" = @(
                @{
                  "type"   = "TextBlock"
                  "weight" = "Bolder"
                  "text"   = "**Start**"
                }
              )
            },
            @{
              "type"  = "Column"
              "width" = $indentRight
              "items" = @(
                @{
                  "type" = "TextBlock"
                  "text" = $build.Start
                }
              )
            }
          )
        },
        @{
          "type"    = "ColumnSet"
          "spacing" = "none"
          "columns" = @(
            @{
              "type"  = "Column"
              "width" = 1
              "items" = @(
                @{
                  "type"   = "TextBlock"
                  "weight" = "Bolder"
                  "text"   = if ($build.Status -eq [Status]::In_Progress) { "**Est. End**" } else { "**End**" }
                }
              )
            },
            @{
              "type"  = "Column"
              "width" = $indentRight
              "items" = @(
                @{
                  "type" = "TextBlock"
                  "text" = if ($build.Status -eq [Status]::In_Progress) { $build.EstEnd } else { $build.End } 
                }
              )
            }
          )
        },
        @{
          "type"    = "ColumnSet"
          "spacing" = "none"
          "columns" = @(
            @{
              "type"  = "Column"
              "width" = 1
              "items" = @(
                @{
                  "type"   = "TextBlock"
                  "weight" = "Bolder"
                  "text"   = if ($build.Status -eq [Status]::In_Progress) { "**Est. Duration**" } else { "**Duration**" }
                }
              )
            },
            @{
              "type"  = "Column"
              "width" = $indentRight
              "items" = @(
                @{
                  "type" = "TextBlock"
                  "text" = if ($build.Status -eq [Status]::In_Progress) { $build.EstDuration } else { $build.Duration }
                }
              )
            }
          )
        }
      )
    )
  }

  if ($build.Status -ne [Status]::Success) {
    $body.attachments.content.msteams.entities = $msTeamsEntities
    $body.attachments.content.body.Add(@{
        "type"    = "ColumnSet"
        "spacing" = "none"
        "columns" = @(
          @{
            "type"  = "Column"
            "width" = 1
            "items" = @(
              @{
                "type"   = "TextBlock"
                "weight" = "Bolder"
                "text"   = switch ($msTeamsEntities.Count) {
                  0 { "**Assignee**" }
                  1 { "**Assignee**" }
                  default { "**Assignees**" }
                }
              }
            )
          },
          @{
            "type"  = "Column"
            "width" = $indentRight
            "items" = @(
              @{
                "type" = "TextBlock"
                "wrap" = $true
                "text" = $asigneesText
              }
            )
          }
        )
      })
  }
          
  return $body
}

<#
    .DESCRIPTION
    Send-MSTeamsMessage posts to the MS-Teams API, which converts it into a Adaptive Card - Message. 
  
    .EXAMPLE
    Parameters -|
      $body = "Jack"
      $uri  = "https://host_name/your_teams_webhook_uri" 
    Returns -| 
      HTTP/HTTPS POST response object
  #>
function Send-MSTeamsMessage(
  [Parameter(Mandatory)] [string] $body, 
  [Parameter(Mandatory)] [string] $uri
) {
  $parameters = @{
    "URI"         = $uri
    "Method"      = "POST"
    "Body"        = $body
    "ContentType" = "application/json"
  }
  $response = (Invoke-WebRequest @parameters -UseBasicParsing)
  return $response
}

Export-ModuleMember -Function New-MSTeamsRequestBody
Export-ModuleMember -Function Send-MSTeamsMessage