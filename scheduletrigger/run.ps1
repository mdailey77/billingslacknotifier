# Input bindings are passed in via param block.
param($Timer)

# Get the current time in EST format
$time = Get-Date
$currenttime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date -Date $time), 'Eastern Standard Time')

Write-Host "Request new bearer token"
$form = @{
    grant_type = 'client_credentials'
    client_id = {client_id}
    client_secret = {client_secret}
    resource = 'https://management.azure.com'
}

$tokenreq = Invoke-WebRequest -Uri https://login.microsoftonline.com/..../oauth2/token -Method Post -Form $form | ConvertFrom-Json

$token = ConvertTo-SecureString -String $tokenreq.access_token -AsPlainText -Force

Write-Host "Make request to Cost Management API"

$servicenamebody = @{
    type = 'Usage'
    timeframe = 'MonthToDate'
    dataset = @{
        granularity = 'None'
        aggregation = @{
            totalCost = @{
                name = 'PreTaxCost'
                function = 'Sum'
            }
        }
        grouping = @(
            @{
                type = 'Dimension'
                name = 'ServiceName'
            }
        )
    }
}

$resourcegroupbody = @{
    type = 'Usage'
    timeframe = 'MonthToDate'
    dataset = @{
        granularity = 'None'
        aggregation = @{
            totalCost = @{
                name = 'PreTaxCost'
                function = 'Sum'
            }
        }
        grouping = @(
            @{
                type = 'Dimension'
                name = 'ResourceGroup'
            }
        )
    }
}

$servicenameresponse = Invoke-WebRequest -Uri https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.CostManagement/query?api-version=2021-10-01 -Method Post -ContentType 'application/json' -Authentication Bearer -Token $token -Body ($servicenamebody|ConvertTo-Json -Depth 5)

$resourcegroupresponse = Invoke-WebRequest -Uri https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.CostManagement/query?api-version=2021-10-01 -Method Post -ContentType 'application/json' -Authentication Bearer -Token $token -Body ($resourcegroupbody|ConvertTo-Json -Depth 5)

$servicenamejson = $servicenameresponse | ConvertFrom-Json
$servicenamerows = $servicenamejson.properties.rows;

$resourcegroupjson = $resourcegroupresponse | ConvertFrom-Json
$resourcegrouprows = $resourcegroupjson.properties.rows;

$totalcost;

#Generate Slack message block
$serviceheader = @{
        type = 'section'
        text = @{
            type = 'mrkdwn'
            text = '*Service Name*'
        }
    }

$serviceitems = foreach ($s in $servicenamerows) {
    @{
        type = 'section'
        text = @{
            type = 'mrkdwn'
            text = "{0}    {1:C2}`r" -f $s[1], $s[0]
        }
    }
    
}

$resourceheader = @{
        type = 'section'
        text = @{
            type = 'mrkdwn'
            text = '*Resource Group*'
        }
    }

$resourcegroupitems = foreach ($r in $resourcegrouprows) {
    $totalcost += $r[0]
    if ($r[1] -eq ''){
        $r[1] = 'devops'
    }
    @{
        type = 'section'
        text = @{
            type = 'mrkdwn'
            text = "{0}     {1:C2}`r" -f $r[1], $r[0]
        }
    }
    
}

$totalcostgroup = @{
        type = 'section'
        text = @{
            type = 'mrkdwn'
            text = "*Total Cost*    {0:C2}" -f $totalcost
        }
    }

$msgdata = @{
    blocks = @(
                 @{
                    type = 'header'
                    text =  @{
                        type = 'plain_text'
                        text = "Month-To-Date Accumulated Costs"
                    }
                }
                @{'type'='divider'}
            )
        }

$contextfooter = @{
        type = 'context'
        elements = @(
            @{
                type = 'plain_text'
                text = "This is an automated message that was run on {0}" -f $currenttime
            }
            
        )
    }

$msgdata.blocks += $serviceheader
$msgdata.blocks += $serviceitems
$msgdata.blocks += @{'type'='divider'}
$msgdata.blocks += $resourceheader
$msgdata.blocks += $resourcegroupitems
$msgdata.blocks += @{'type'='divider'}
$msgdata.blocks += $totalcostgroup
$msgdata.blocks += @{'type'='divider'}
$msgdata.blocks += $contextfooter

Write-Host "Send message to Slack"
Invoke-WebRequest -Uri https://hooks.slack.com/services/.../... -Method Post -Body ($msgdata|ConvertTo-Json -Depth 5) -ContentType 'application/json'

