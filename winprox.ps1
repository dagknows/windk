param (
    [string]$url
)
$url = $url -replace "^dk://", "https://"

Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Windows.Forms

# The URL from which you want to extract the string
# $url = "https://dev.dagknows.com/tasks/urVBfYgPpGU74mqGClZH/execute"

# Use regex to extract the random string (assuming it's always between 'tasks/' and '/execute')
$pattern = [regex]::Match($url, "/tasks/([a-zA-Z0-9]+)")

# Get the value of the first capture group
if ($pattern.Success) {
    $runbook_task_id = $pattern.Groups[1].Value
    Write-Host "Extracted string: $runbook_task_id"
} else {
    Write-Host "No match found."
}

function createTicket {
    param (
        [string]$job_id
    )    

    [System.Windows.Forms.MessageBox]::Show("Hey there.  Job ID: $($job_id)", "Alert", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    
}

$dialogScript = {
    param($proxy_domain, $runbook_task_id, $token, $current_job_file, $job_id, $user_info, $dagknows_url, $exit_file, $debug_file)
    # Use a suitable dialog method, like a custom function or a .NET dialog
    Add-Type -AssemblyName System.Windows.Forms

    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Dagknows Troubleshooting"
        $form.Width = 470
        $form.Height = 150
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $form.TopMost = $true
        #$form.ControlBox = $false

        $form.Add_FormClosing({
            Set-Content -Path "$exit_file" -Value "Exit now"
        })

        # Create a Label to display the message
        $label = New-Object System.Windows.Forms.Label
        $label.Text = "Starting."
        $label.AutoSize = $true
        $label.Top = 30
        $label.Left = 50
        $form.Controls.Add($label)

        # Second label to display the secondary message to prevent the illusion of getting stucked
        # (for long running task, try to display the last line of output)
        $sedondLabel = New-Object System.Windows.Forms.Label
        $sedondLabel.Text = ""
        $sedondLabel.AutoSize = $true
        $sedondLabel.Top = 50
        $sedondLabel.Left = 50
        $form.Controls.Add($sedondLabel)        

        # Add a button to close the form
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000
        $problemResolvedButton = New-Object System.Windows.Forms.Button
        $problemResolvedButton.Text = "Problem resolved"
        $problemResolvedButton.Top = 70
        $problemResolvedButton.Left = 70
        $problemResolvedButton.Width = 150
        $problemResolvedButton.Add_Click({ 
            Set-Content -Path "$exit_file" -Value "Exit now"
            $form.Close() 
            $host.SetShouldExit(1)
        })
        $problemResolvedButtonVisible = $false


        $problemNotResolvedButton = New-Object System.Windows.Forms.Button
        $problemNotResolvedButton.Text = "Not resolved (Create Ticket)"
        $problemNotResolvedButton.Top = 70
        $problemNotResolvedButton.Left = 240  # Position it next to the first button
        $problemNotResolvedButton.Width = 160  # Specify the width of the second button
        $problemNotResolvedButton.Add_Click({
            # Add action for the "Resolved" button here
            $createTicketScriptBlock = {
                function getEnvVar {
                    param (
                        [Parameter(Mandatory=$true)]
                        [string]$key
                    )
                    return [System.Environment]::GetEnvironmentVariable($key)
                }                

                # First, get the title of the original runbook task
                $apiUrl = $dagknows_url + "/api/tasks/" + $runbook_task_id + ""
                $headers = @{
                    "Content-Type" = "application/json"
                    "Authorization" = "Bearer $token"
                }
                $response = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $headers 
                $runbook_task_title = $response.task.title
                
                $jiraUserName = getEnvVar("JIRA_USER_NAME")
                $jiraApiKey = getEnvVar("JIRA_API_KEY")
                $jiraBaseUrl = getEnvVar("JIRA_BASE_URL")
                
                $projectKey = "DD"
                $issueType = "Task"
                # Define the API endpoint for creating an issue
                $ticketUrl = "$jiraBaseUrl/rest/api/2/issue/"
                
                # Prepare the headers and payload for the request
                $combo = $jiraUserName + ":" + $jiraApiKey
                $authValue = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($combo))
                $headers = @{
                    "Content-Type" = "application/json"
                    "Accept" = "application/json"
                    "Authorization" = "Basic $authValue"
                }
                
                $projectUrl = "$jiraBaseUrl/rest/api/2/issue/createmeta?projectKeys=$projectKey"
                # Job URL should be referencing the original $runbook_task_id not the ticket_task_id
                $job_url = "$dagknows_url/tasks/$($runbook_task_id)?job_id=$job_id&iter=0"
                $ticket_body = "User:`n$($user_info.("first_name")) $($user_info.("last_name"))`nIssue:$runbook_task_title`nInfo:$job_url"
                $summary = $runbook_task_title
                $description = $ticket_body
                
                $payload = @{
                    fields = @{
                        project = @{
                            key = $projectKey
                        }
                        summary = $summary
                        description = $description
                        issuetype = @{
                            name = $issueType
                        }
                    }
                } | ConvertTo-Json -Depth 10
                
                Add-Content -Path "$debug_file" -Value "Ticket URL: $ticketUrl"
                Add-Content -Path "$debug_file" -Value "Payload: $payload"
                Add-Content -Path "$debug_file" -Value "jiraUserName: $jiraUserName, jiraApiKey: $jiraApiKey, jiraBaseUrl: $jiraBaseUrl"
                # Make the POST request to create the Jira ticket
                $response = Invoke-RestMethod -Uri $ticketUrl -Headers $headers -Method Post -Body $payload

                if ($response -and $response.key) {
                    $ticketId = $response.key
                    Set-Content -Path "$current_job_file" -Value "Ticket created: $ticketId"
                    Add-Content -Path "$debug_file" -Value "Ticket ID: $ticketId"
                    Write-Output $ticketId
                }

                <#
                param($proxy_domain, $runbook_task_id, $token, $current_job_file, $job_id, $user_info, $dagknows_url)
    
                $ticket_task_id = $Env:TICKET_TASK_ID
                if ($runbook_task_id -ne $ticket_task_id) {
                    # First, get the title of the original runbook task
                    $apiUrl = $dagknows_url + "/api/tasks/" + $runbook_task_id + ""
                    $headers = @{
                        "Content-Type" = "application/json"
                        "Authorization" = "Bearer $token"
                    }
                    $response = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $headers 
                    $runbook_task_title = $response.task.title
    
                    # Job URL should be referencing the original $runbook_task_id not the ticket_task_id
                    $job_url = "$dagknows_url/tasks/$($runbook_task_id)?job_id=$job_id&iter=0"
                    $ticket_body = "User:`n$($user_info.("first_name")) $($user_info.("last_name"))`nIssue:$runbook_task_title`nInfo:$job_url"
                    $params = @{
                        "summary" = $runbook_task_title
                        "description" = $ticket_body
                    }
                    # Now make a request.
                    $conv_id = "tconv_" + $ticket_task_id
                    $body = @{
                    "job"= @{
                        "proxy_alias"="win"
                        "param_values"=$params
                        "special_param_values"=@{}
                        "output_params"=@{}
                        "runbook_task_id"=$ticket_task_id
                        "starting_child_path"=""
                        "conv_id"=$conv_id
                    }
                    }
                    $jsonBody = $body | ConvertTo-Json
                    $apiUrl = $dagknows_url + "/api/tasks/" + $ticket_task_id + "/execute"
                    $response = Invoke-RestMethod -Uri $apiUrl -Method POST -Headers $headers -Body $jsonBody
                }
                #>
            } # Endo of $createTicketScriptBlock
    
            # If the user clicked on the "Create Ticket" button, invoke the $createTicketScriptBlock
            # update the message, change label on button, show / hide buttons, and refresh the form 
            # to update the display
            $result = $createTicketScriptBlock.Invoke($proxy_domain, $runbook_task_id, $token, $current_job_file, $job_id, $user_info, $dagknows_url)
    
            $timer.Stop()
            $label.Text = "Creating ticket."
            $problemNotResolvedButton.Visible = $false
            $problemNotResolvedButton.Hide()
            $form.Controls.Remove($problemNotResolvedButton)
            $problemResolvedButton.Text = "OK"
            $problemResolvedButton.Visible = $false
            $problemResolvedButton.Hide()
            $form.Invalidate()
            $form.Update()
            $form.Refresh()
            Start-Sleep -Second 4
            $label.Text = "Ticket created:" + $result
            $problemResolvedButton.Visible = $true
            $form.Invalidate()
            $form.Update()
            $form.Refresh()
    
            #$problemNotResolvedButton.Dispose()
            
            #createTicket($job_id)
            #$form.Close()
            #$host.SetShouldExit(1)
        }) # End of Add_Click for $problemNotResolvedButton

        $problemNotResolvedButtonVisible = $false 

        $timer.Add_Tick({
            #$content = Get-Content -Path $current_job_file -Raw
            $firstLine = Get-Content -Path $current_job_file -TotalCount 1
            $lastLine = Get-Content -Path $current_job_file | Select-Object -Last 1
            $firstLine = $firstLine.Trim()
            $lastLine = $lastLine.Trim() 

            if ($firstLine -eq $lastLine) {
                $lastLine = ""
            }

            $firstLine = if ($firstLine.Length -gt 70) { $firstLine.Substring(0, 70) } else { $firstLine }

            if ($lastLine.Length -gt 60) {
                $lastLine = $lastLine.Substring([math]::Max(0, $lastLine.Length - 60)) # Display only the last 10 characters
                $lastLine = ($lastLine -split ' ', 2)[1] # Remove the first word that is not complete.    
            }

            $current_timestamp = Get-Date -Format "hh:mm:ss"
            $lastLine = $lastLine + " " + $current_timestamp

            if ($firstLine -ne "") {
                $label.Text = $firstLine
            }
            $sedondLabel.Text = $lastLine
    
            if ($firstLine.StartsWith("Runbook finished")) {
                if (-not $problemResolvedButtonVisible) {
                    $form.Controls.Add($problemResolvedButton)
                    $problemResolvedButtonVisible = $true
                }
    
                if (-not $problemNotResolvedButtonVisible) {
                    $form.Controls.Add($problemNotResolvedButton)
                    $problemNotResolvedButtonVisible = $true
                }
                $problemResolvedButton.Visible = $true
                $problemResolvedButton.Show()
                $problemNotResolvedButton.Visible = $true 
                $problemNotResolvedButton.Show()
    
            } else {
                $problemResolvedButton.Visible = $false
                $problemResolvedButton.Hide()
                $problemResolvedButton.Visible = $true
                $problemResolvedButton.Hide()
            }
            $form.Invalidate()
            $form.Update()
            $form.Refresh()

            $form.TopMost = $true
            #$form.Activate()

        })
    
        $form.Add_Shown({ 
            $timer.Start() 
            $form.TopMost = $true
            $form.Activate()
        })
        $form.Add_FormClosed({ $timer.Stop() })
    
        # Show the form
        $form.ShowDialog() | Out-Null

    } catch {
        # Ignore the "The pipeline has been stopped" exception if it was ever thrown somehow
    }
}

$proxy_block = {
    param (
        [string]$runbook_task_id,
        [string]$proxy_ws,
        [string]$proxy_http,
        [string]$proxy_domain,
        [string]$token,
        [string]$working_directory
    )


    function Ensure-DirectoryExists {
        param (
            [string]$directoryPath
        )    

        # Check if the directory exists
        if (-not (Test-Path -Path $directoryPath)) {
            # Create the directory if it does not exist
            New-Item -ItemType Directory -Path $directoryPath
            Write-Output "Directory created: $directoryPath"
        }    
    }

    function Start-WebSocketListener {
        param (
            [string]$runbook_task_id,
            [string]$proxy_ws,
            [string]$proxy_http,
            [string]$proxy_domain,
            [string]$token,
            [string]$working_directory,
            [string]$exit_file
        )


        # Define your Bearer token
        # Define the WebSocket server URI (ensure it starts with wss:// for a secure connection)
        # $uri = [System.Uri]::new("wss://dev.dagknows.com/wsfe/proxies/agents/connect")
        $websocket = New-Object System.Net.WebSockets.ClientWebSocket
        $websocket.Options.SetRequestHeader("Authorization", "Bearer $token")
        $uri = [System.Uri]::new($proxy_ws + $proxy_domain + "/wsfe/proxies/agents/connect")
        $execs_url = $proxy_ws + $proxy_domain + "/wsfe"
        $dagknows_url = $proxy_http + $proxy_domain
        $apiUrl = $dagknows_url + "/api/tasks/" + $runbook_task_id + "/execute"
        
        # param($websocket, $uri, $dagknows_url, $execs_url)

        Write-Host "Trying to connect to ws" 

        try {
            # Connect to the WebSocket server
            #Write-Host "Really trying"
            $websocket.ConnectAsync($uri, [Threading.CancellationToken]::None).Wait()
            #Write-Host "Done waiting"

            if ($websocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                Write-Host "WebSocket connection established."

                $params = @{
                    "x" = 3
                    "y" = 5
                }
                # Now make a request.
                $conv_id = "tconv_" + $runbook_task_id
                $headers = @{
                    "Content-Type" = "application/json"
                    "Authorization" = "Bearer $token"
                }
                $body = @{
                "job"= @{
                    "proxy_alias"="win"
                    "param_values"=$params
                    "special_param_values"=@{}
                    "output_params"=@{}
                    "runbook_task_id"=$runbook_task_id
                    "starting_child_path"=""
                    "conv_id"=$conv_id
                }
                }
                $jsonBody = $body | ConvertTo-Json
                if (($null -ne $runbook_task_id) -and ($runbook_task_id -ne "")) {
                    Write-Host "Making a POST request"
                    Write-Host "URL: " $apiUrl
                    #Write-Host "Headers: " $headers
                    #Write-Host "Body: " $jsonBody
                    $response = Invoke-RestMethod -Uri $apiUrl -Method POST -Headers $headers -Body $jsonBody
                    #Write-Host ($response | ConvertTo-Json -Depth 4)    
                } else {
                    Write-Host "Runbook task ID was NOT specified"
                }

                # Keep listening for messages in a loop
                Write-Host "Listening for incoming messages..."
                while ($websocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                    $receiveBuffer = New-Object -TypeName byte[] -ArgumentList 4096
                    $receivedData = [System.IO.MemoryStream]::new()

                    do {
                        $receiveSegment = [System.ArraySegment[byte]]::new($receiveBuffer)
                        $receiveTask = $websocket.ReceiveAsync($receiveSegment, [Threading.CancellationToken]::None)
                        $receiveTask.Wait()

                        $result = $receiveTask.Result

                        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                            Write-Host "Server initiated close. Closing the connection."
                            $websocket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Closing", [Threading.CancellationToken]::None).Wait()
                            break
                        }

                        $receivedData.Write($receiveBuffer, 0, $result.Count)
                    } while (-not $result.EndOfMessage)

                    if ($receivedData.Length -gt 0) {
                        $receivedBytes = $receivedData.ToArray()
                        $receivedMessage = [System.Text.Encoding]::UTF8.GetString($receivedBytes)
                        $receivedJson = $receivedMessage | ConvertFrom-Json
                        $receivedJsonPretty = $receivedJson | ConvertTo-Json -Depth 4
                        # Write-Host "Message received: $receivedJsonPretty"
                        $debug_file = Join-Path -Path $working_directory -ChildPath "debug.txt" 
                        "" > $debug_file
                        #$receivedJsonPretty > $debug_file
                        $user_info = $receivedJson.message.user_info
                        $conv_id = $receivedJson.message.req.req_obj.conv_id
                        $iter = $receivedJson.message.req.req_obj.iter
                        $code_lines = $receivedJson.message.req.req_obj.code
                        $job_id = $receivedJson.message.req.job_id
                        $role_token = $receivedJson.token
                        $runbook_task_id = $receivedJson.message.req.req_obj.runbook_task_id
                        $starting_child_path = $receivedJson.message.req.req_obj.starting_child_path
                        $task_id = $receivedJson.message.req.req_obj.task_id

                        $job_folder = Join-Path -Path $working_directory -ChildPath "jobs" 
                        Ensure-DirectoryExists -directoryPath $job_folder

                        $fileName = "\jobs\$job_id.ps1"
                        if ($job_id -ne $null) {
                            $fullPath = Join-Path -Path $working_directory -ChildPath $fileName 
                            $current_job_file = Join-Path -Path $working_directory -ChildPath "jobs/current_job.txt" 
                            $streamWriter = [System.IO.StreamWriter]::new($fullPath, $false, [System.Text.Encoding]::UTF8)
                            $final_execs_url = $execs_url 
                            $other_info = '$conv_id = "' + $conv_id + '"' + "`n" +
                                        '$iter = "' + $iter + '"' + "`n" +
                                        '$token = "' + $role_token + '"' + "`n" +
                                        '$execs_url = "' + $final_execs_url + '"' + "`n" +
                                        '$global:dagknows_url = "' + $dagknows_url + '"' + "`n" + 
                                        '$user_info = ' + "'" + ($user_info | ConvertTo-Json -Compress) + "'" + "`n" + 
                                        '$user_info = ' + 'ConvertTo-Hashtable($user_info | ConvertFrom-Json)' + "`n"
                            
                            foreach ($line in $code_lines) {
                                if ($line.Contains("DK_OTHER_INFO")) {
                                    $streamWriter.WriteLine($other_info)
                                } else {
                                    $streamWriter.WriteLine($line)
                                }
                            }

                            $streamWriter.Close()
                            Write-Host "Full path:" $fullPath
                            
                            if (-not $global:modal_box_visible) {
                                Set-Content -Path $current_job_file -Value " "
                                $global:dialog_job = Start-Job -ScriptBlock $dialogScript -ArgumentList $proxy_domain, $runbook_task_id, $token, $current_job_file, $job_id, $user_info, $dagknows_url, $exit_file, $debug_file
                                $global:modal_box_visible = $true
                            }

                            #$fullPath >> $debug_file

                            #Write-Host "BEFORE RUNNING THE PROGRAM"
                            #& $fullPath  
                            $task_job = Start-Job -ScriptBlock { & $using:fullPath }
                            Wait-Job -Job $task_job
                            #Write-Host "AFTER RUNNING THE PROGRAM"

                            #$websocket.Dispose()  
                            break
                        }
                        $receivedData.SetLength(0) # Clear the MemoryStream for the next message
                    }
                }

                Write-Host "WebSocket connection closed."
            } else {
                Write-Host "Failed to establish WebSocket connection."
            }
        }
        catch {
            Write-Error "An error occurred: $_.Exception"
        }
        finally {
            # Dispose of the WebSocket instance
            Write-Host "Websocket connection disposed inside the finally block"
            $websocket.Dispose()
        }
    }

    #Write-Host "runbook_task_id: $runbook_task_id, proxy_ws: $proxy_ws, proxy_http: $proxy_http, proxy_domain: $proxy_domain, WORKING_DIRECTORY: $working_directory"
    $exit_file = Join-Path -Path $working_directory -ChildPath "exit.txt" 
    # We are using multiple background jobs, and using file to determine when the main process should terminate
    # Before we start, remove the exit file
    if (Test-Path -Path $exit_file) {
        Remove-Item -Path $exit_file
    }

    Start-WebSocketListener -runbook_task_id $runbook_task_id -proxy_ws $proxy_ws -proxy_http $proxy_http -proxy_domain $proxy_domain -token $token -working_directory $working_directory -exit_file $exit_file

    # While the exit file is not present, sleep and wait for it.
    # The exit file is only created if the user interact with the dialog
    while(-not (Test-Path $exit_file)) {
        Start-Sleep -Seconds 2
    }

    # Now that the exit file is present, clean up (remove it and gracefully terminate)
    if (Test-Path -Path $exit_file) {
        Remove-Item -Path $exit_file
    }
}


$token = $Env:PROXY_TOKEN
$proxy_domain = $Env:PROXY_DOMAIN
$proxy_secure = $Env:PROXY_SECURE.Trim().ToLower().Trim("'").Trim('"')


#$proxy_domain = "dev.dagknows.com"
#$token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJkYWdrbm93cy5jb20iLCJzdWIiOiJzYXJhbmdAZGFna25vd3MuY29tIiwibmJmIjoxNzMwMDkwNzE4LCJleHAiOjE3NjE2MjY4OTgsImp0aSI6Imd2U2I2U21iU2FSUzR6RlYiLCJhdWQiOiJkYWdrbm93cyIsInJvbGUiOiJzdXByZW1vIiwidXNlcl9jbGFpbXMiOnsidWlkIjoiMSIsInVuYW1lIjoic2FyYW5nQGRhZ2tub3dzLmNvbSIsIm9yZyI6ImRhZ2tub3dzIiwiZmlyc3RfbmFtZSI6IlNhcmFuZyIsImxhc3RfbmFtZSI6IkRoYXJtYXB1cmlrYXIiLCJyb2xlIjoiU3VwcmVtbyIsImFlc19rZXkiOiIxLVxuTURCTEMtOEx0ZkF1cm9sOUNHMExcbmZLTEIzclxudSIsIm9mc3QiOlszMTQsNDI2LDkxLDEzNCw0MjAsNDI0LDI3NywxOTcsNDQ5LDMzNiw0MzgsMzQ1LDMwMSw0MDUsMTAyLDE4OSwxNTksMTc0LDQwNiw2NiwzMDgsMzc0LDQzOCw0MjUsMTg1LDY1LDI3Nyw5MCwyMDAsMzg0LDIyMSwxMTZdfX0.hm2QvlTSsHslkrT9Db0lEZcs_qcrm2xkGp_pXahuYLfnhuYSfUkc7GeoynoKX2J37DJPaEglNKkEaJKL4rbxlX7kPVHD6ElKc8Se_csNOAHzTQf4h013be-uAaeC2Uo7Pb4ZO5uwquHi2Jqz0LbdtWOtlCFjIjOGugLK26rChJjFfqVLERYsgOXjaTwVqOGUfhT-OFJDaoBbHZAmrIB-UkkMKdIBKcto0DwQSOeyj4nv69htrLrGUheuHQkfE9gEKlaqWyynzx0MZIStjPkPheMzbk-AajrDO5GbaCh46AZEs_zl2_kq1OcgyC0QFrL2Wm5wsQ_gt7XhsMyMbvkOgQ"

#Write-Host "PROXY_DOMAIN: " $proxy_domain 
#Write-Host "PROXY_SECURE: " $proxy_secure
#Write-Host "PROXY_TOKEN: " $token

#$proxy_secure = $true
#$proxy_secure = [System.Boolean]::Parse($proxy_secure)

if ($proxy_secure -eq "true") {
    $proxy_secure = $true
} else {
    $proxy_secure = $false
}

$proxy_ws = "ws://"
$proxy_http = "http://"
if ($proxy_secure) {
    $proxy_ws = "wss://"
    $proxy_http = "https://"
}

#Write-Host "VERSION: " $PSVersionTable.PSVersion

$global:modal_box_visible = $false
$global:dialog_job = $null
$proxy_block.Invoke($runbook_task_id, $proxy_ws, $proxy_http, $proxy_domain, $token, $PSScriptRoot)
#Write-Host "Please respond to the appropriate option in the dialog."
