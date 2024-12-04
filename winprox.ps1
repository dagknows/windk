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
    $runbook_task_id = ""
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
    #Add-Type -AssemblyName System.Windows.Forms.LinkLabel

    $global:buttonClicked = $null  # Variable to store which button was clicked

    try {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Dagknows Troubleshooting"
        $form.Width = 470
        $form.Height = 150
        #$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $form.Location = New-Object System.Drawing.Point(200, 200)
        $form.TopMost = $true
        #$form.ControlBox = $false

        # Create a Label to display the message
        $label = New-Object System.Windows.Forms.Label
        $label.Text = "Runbook finished"
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

        $ticketLabel = New-Object System.Windows.Forms.LinkLabel
        $ticketLabel.Text = ""  
        $ticketLabel.AutoSize = $true
        $ticketLabel.Top = 30
        $ticketLabel.Left = 150
        $ticketLabel.Visible = $false
        $form.Controls.Add($ticketLabel)


        # Add a button to close the form
        $problemResolvedButton = New-Object System.Windows.Forms.Button
        $problemResolvedButton.Text = "Problem resolved"
        $problemResolvedButton.Top = 70
        $problemResolvedButton.Left = 70
        $problemResolvedButton.Width = 150
        $problemResolvedButton.Add_Click({ 
            if ($global:buttonClicked -eq $null) {
                # Currently, this button is shared in both scenarios, "Problem resolved" and "Not resolved".
                # So, if the user clicked on "Not resolved" first, don't change its value here, so that we 
                # know which button was clicked and perform appropriate action.
                # If the user clicked on "Problem resolved" first, we are supposed to shutdown the proxy.
                # If the user clicked on "Not resolved" first, we are supposed to keep the proxy running for 
                # some time so that the technical service engineer can perform additional action on the user 
                # machine.  In this case, we are supposed to minimize the terminal somehow.
                $global:buttonClicked = "problem_resolved"
            }
            # Set-Content -Path "$exit_file" -Value "problem_resolved"
            $form.Close();
        })
        $problemResolvedButtonVisible = $false


        $problemNotResolvedButton = New-Object System.Windows.Forms.Button
        $problemNotResolvedButton.Text = "Not resolved (Create Ticket)"
        $problemNotResolvedButton.Top = 70
        $problemNotResolvedButton.Left = 240  # Position it next to the first button
        $problemNotResolvedButton.Width = 160  # Specify the width of the second button
        $problemNotResolvedButton.Add_Click({
            $global:buttonClicked = "not_resolved"
            # Add action for the "Resolved" button here
            $createTicketScriptBlock = {
                function getEnvVar {
                    param (
                        [Parameter(Mandatory=$true)]
                        [string]$key
                    )
                    return [System.Environment]::GetEnvironmentVariable($key)
                }                

                $no_ticket_creation = getEnvVar('DK_NO_TICKET_CREATION')
                if ($no_ticket_creation -eq "true") {
                    Write-Output "DD-1441"
                    return
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
                
                #Add-Content -Path "$debug_file" -Value "Ticket URL: $ticketUrl"
                #Add-Content -Path "$debug_file" -Value "Payload: $payload"
                #Add-Content -Path "$debug_file" -Value "jiraUserName: $jiraUserName, jiraApiKey: $jiraApiKey, jiraBaseUrl: $jiraBaseUrl"
                # Make the POST request to create the Jira ticket
                $response = Invoke-RestMethod -Uri $ticketUrl -Headers $headers -Method Post -Body $payload

                if ($response -and $response.key) {
                    $ticketId = $response.key
                    #Set-Content -Path "$current_job_file" -Value "Ticket created: $ticketId"
                    #Add-Content -Path "$debug_file" -Value "Ticket ID: $ticketId"
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
            #$result = "DD-1441"
    
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
            $label.Text = "Ticket created:"

            # Create a LinkLabel to display a hyperlink
            $ticketLabel.Text = $result

            # Handle the LinkClicked event
            $ticketLabel.Add_LinkClicked({
                param($sender, $eventArgs)
    
                # Retrieve the LinkData safely
                if ($eventArgs.Link -ne $null -and $eventArgs.Link.LinkData -ne $null) {
                    # Check if the left mouse button was used
                    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                        Start-Process $eventArgs.Link.LinkData
                    }
                } else {
                    #Write-Host "No valid link data available."
                }
            })
            $ticketLabel.LinkArea = New-Object System.Windows.Forms.LinkArea(0, $result.Length) # Specify which part of the text is clickable    
            $ticketLabel.Links[0].LinkData = "https://dagknows.atlassian.net/issues/" + $result # URL to open.  Hard-coding the URL here for now

            #$ticketLabel.Links.Clear() # Clear existing links to avoid duplication
            #$ticketLabel.Links.Add(0, $result.Length, "https://dagknows.atlassian.net/issues/" + $result) # Add link with proper range and data
            $ticketLabel.Visible = $true
            $ticketLabel.Show()

            $problemResolvedButton.Visible = $true
            $form.Invalidate()
            $form.Update()
            $form.Refresh()
    
            #$problemNotResolvedButton.Dispose()
            
            #createTicket($job_id)
            #$form.Close()

        }) # End of Add_Click for $problemNotResolvedButton

        $problemNotResolvedButtonVisible = $false 
    
        $form.Add_Shown({ 

            $firstLine = "Runbook finished.  Please confirm if the problem has been resolved."
            $lastLine = ""
            #$content = Get-Content -Path $current_job_file -Raw
            #$firstLine = Get-Content -Path $current_job_file -TotalCount 1
            #$lastLine = Get-Content -Path $current_job_file | Select-Object -Last 1
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
            #$sedondLabel.Text = $lastLine
            $sedondLabel.Text = ""
    
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
            $form.Activate()
        })

        $form.Add_FormClosing({
            #Set-Content -Path "$exit_file" -Value "Exit now"
            ;
        })

        $form.Add_FormClosed({ 
            #$timer.Stop() 
            ;
        })
    
        # Show the form
        $form.ShowDialog() | Out-Null

    } catch {
        # Ignore the "The pipeline has been stopped" exception if it was ever thrown somehow
    }

    return $global:buttonClicked
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

    function wsfe_proxy_connect {
        param (
            [string]$token,
            [string]$proxy_ws,
            [string]$proxy_domain,
            [bool]$verbose
        )    

        $uri = [System.Uri]::new($proxy_ws + $proxy_domain + "/wsfe/proxies/agents/connect")

        $itercount = 0
        while ($itercount -lt 50) {
            $errored = $false
            try {
                #Write-Host "Trying to create websocket"
                $websocket = New-Object System.Net.WebSockets.ClientWebSocket
                $websocket.Options.SetRequestHeader("Authorization", "Bearer $token")
                $websocket.ConnectAsync($uri, [Threading.CancellationToken]::None).Wait()
            } catch {
                $errored = $true
                #Write-Host "Error: $($_.Exception.Message)"
                #Write-Host "URI: " $uri
                #Write-Host "StackTrace: $($_.Exception.StackTrace)"
            }

            if ($websocket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
                $errored = $true
            }

            if ($errored) {
                $websocket.Dispose()
                $itercount = $itercount + 1
                Write-Host "Attempt: " $itercount
                Start-Sleep -Seconds 2
                continue
            } else {
                break
            }
        }

        if ($websocket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            Write-Host "Unable to establish connection to wsfe for proxy.  Giving up."
            exit 1
        } else {
            if ($verbose) {
                Write-Host "WebSocket connection established."
            }
            return $websocket
        }
    }

    function send_ping {
        param (
            [object]$websocket,
            [string]$connId
        )

        try {
            $jsonPayload = @{
                type = "ping"
                connId  = $connId
            } | ConvertTo-Json -Depth 10
            
            # Convert JSON payload to bytes
            $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
            
            # Send the JSON payload
            $buffer = [System.ArraySegment[byte]]::new($payloadBytes)
            $websocket.SendAsync($buffer, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
            
            # Create a buffer to receive the response
            #$responseBuffer = New-Object byte  # Initialize a byte array of size 1024 (or desired size)
            #$responseSegment = [System.ArraySegment[byte]]::new($responseBuffer)
            
            # Receive the response
            #$response = $websocket.ReceiveAsync($responseSegment, [Threading.CancellationToken]::None).Result
            
            # Decode the response
            #$responseText = [System.Text.Encoding]::UTF8.GetString($responseBuffer, 0, $response.Count)
            #Write-Host "Received response: $responseText"

        } catch {
            # If the ping fails for any reason, it is probably ok to ignore it.
            ;
        }
    }
    
    function wait_for_proxy_ready {
        # After the proxy establish connection to wsfe, wsfe seems to send some messages to 
        # the proxy.  I am not sure how this is done on the wsfe side, or why it is done automatically.
        # Perhaps, this should not be done automatically.  Perhaps, this should only be done, when the 
        # proxy send certain message to wsfe.  When wsfe send these messages automatically, it makes it 
        # difficult for the proxy to reliably handle these messages in some situation.  Anyway, these 
        # messages includes "setPublicKey", "runners/python/updateDaglib", and some ping.  For now, 
        # this function waits until we received these messages.  Only until we have received these 
        # messages then we can submit the job for the intended runbook.
        param (
            [object]$websocket,
            [string]$token,
            [string]$proxy_ws,
            [string]$proxy_domain
        )

        $first_ping_received = $false

        while ($true) {
            try {
                $receiveBuffer = New-Object -TypeName byte[] -ArgumentList 4096
                $receivedMessage = retrieve_message -websocket $websocket -receiveBuffer $receiveBuffer
                if ($receivedMessage -eq "exception") {
                    $websocket.Dispose()
                    $websocket = wsfe_proxy_connect -token $token -proxy_ws $proxy_ws -proxy_domain $proxy_domain -verbose $false
                    continue
                } elseif ($receivedMessage -eq "timeout") {
                    continue
                } elseif ($receivedMessage -eq "closed") {
                    # If the server really closed the connection, what should we do?  I am not really sure on what to do in this case.
                    Start-Sleep -Seconds 2
                    $websocket.Dispose()
                    $websocket = wsfe_proxy_connect -token $token -proxy_ws $proxy_ws -proxy_domain $proxy_domain -verbose $false
                    continue
                } else {
                    $receivedJson = $receivedMessage | ConvertFrom-Json
                    $receivedJsonPretty = $receivedJson | ConvertTo-Json -Depth 4
                    # Write-Host "Message received: $receivedJsonPretty"
                    $debug_file = Join-Path -Path $working_directory -ChildPath "debug.txt" 
                    #"" > $debug_file
                    #$receivedJsonPretty >> $debug_file
                    $type = $receivedJson.type 
                    $cmd = $receivedJson.cmd 
                    
                    $job_id = $receivedJson.message.req.job_id

                    if ($job_id -ne $null) {
                        # If we happens to receive a message with a job_id inside this function, it is 
                        # probably ok to ignore that message because that message is probably not 
                        # intended for this proxy because technically this proxy has not submit it the 
                        # job for the intended runbook yet.  I am not sure if we will ever receive  a 
                        # message with a job_id here.
                        ;
                    }

                    if ("ping" -eq $type) {
                        $first_ping_received = $true
                        $connId = $receivedJson.connId
                        Write-Host "Sending ping.  connId:" $connId (Get-Date)
                        send_ping -websocket $websocket -connId $connId
                        #Write-Host "Part 3 received."
                    }

                    if ($first_ping_received) {
                        break
                    } else {
                        Write-Host "Please wait.  Proxy is still starting up."
                    }
                }

            } catch {
                $exception_message = $_.Exception.Message + "`n" + $_.Exception.StackTrace
                #Write-Host "An unexpected error occurred inside wait_for_proxy_ready: $_"
                #Write-HOst "Stack trace:" 
                #Write-Host $_.Exception.StackTrace
                #Write-HOst "Retrying.." 
                $websocket.Dispose()
                $websocket = wsfe_proxy_connect -token $token -proxy_ws $proxy_ws -proxy_domain $proxy_domain -verbose $false
            }
        }

        # After receiving setPublicKey, and "runners/python/updateDaglib", sleep for some small period of time 
        # to make sure that the wsfe is fully ready from the backend.
        Start-Sleep -Seconds 1
        return $websocket
    }

    function retrieve_message {
        param (
            [object]$websocket,
            [byte[]]$receiveBuffer
        )
    
        $receivedData = New-Object System.IO.MemoryStream
        $control_c_original = [Console]::TreatControlCAsInput
        $final_result = ""
        $timeout = [TimeSpan]::FromSeconds(5)  # Adjust timeout as needed.
        
        try {
            [Console]::TreatControlCAsInput = $false
                
            do {
                $cts = New-Object System.Threading.CancellationTokenSource
                #$cts.CancelAfter($timeout)
                $receiveSegment = [System.ArraySegment[byte]]::new($receiveBuffer)
                
                try {
                    $receiveTask = $websocket.ReceiveAsync($receiveSegment, $cts.Token)
                    $result = $receiveTask.GetAwaiter().GetResult()
        
                    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                        $final_result = "closed"
                        break
                    }
        
                    $receivedData.Write($receiveBuffer, 0, $result.Count)
                }
                catch [OperationCanceledException] {
                    $final_result = "timeout"
                    break
                }
                catch {
                    $final_result = "exception"
                    break
                }
                finally {
                    $cts.Dispose()
                }
            } while (-not $result.EndOfMessage)
        }
        finally {
            [Console]::TreatControlCAsInput = $control_c_original
        }
    
        if ($final_result -eq "") {
            $receivedData.Seek(0, [System.IO.SeekOrigin]::Begin)
            $final_result = [System.Text.Encoding]::UTF8.GetString($receivedData.ToArray())
        }
    
        return $final_result
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
        Write-Host "Trying to connect to ws" 
        $debug_file = Join-Path -Path $working_directory -ChildPath "debug.txt" 
        "" > $debug_file

        $websocket = wsfe_proxy_connect -token $token -proxy_ws $proxy_ws -proxy_domain $proxy_domain -verbose $true
        $execs_url = $proxy_ws + $proxy_domain + "/wsfe"
        $dagknows_url = $proxy_http + $proxy_domain
        $apiUrl = $dagknows_url + "/api/tasks/" + $runbook_task_id + "/execute"
        
        $job_finished_count = 0
        # param($websocket, $uri, $dagknows_url, $execs_url)

        $websocket = wait_for_proxy_ready -websocket $websocket -token $token -proxy_ws $proxy_ws -proxy_domain $proxy_domain
        $connId = $null
        $initial_ping_sent = $false
        $last_ping_sent_time = Get-Date 
        Write-Host "Proxy should be ready now." 

        try {

            if ($websocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                $params = @{} # These jobs typically do not take parameters.  If they do, we need to parse these parameters from the URL somehow.

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
                    #$response = Invoke-RestMethod -Uri $apiUrl -Method POST -Headers $headers -Body $jsonBody

                    $submit_job = Start-Job {
                        # We want to start a background job to submit the job so that we do not miss any websocket event
                        Invoke-RestMethod -Uri $using:apiUrl -Method POST -Headers $using:headers -Body $using:jsonBody
                    }

                    #Write-Host ($response | ConvertTo-Json -Depth 4)    
                } else {
                    Write-Host "Runbook task ID was NOT specified"
                    # Set the below variable to true to prevent showing the dialog when the proxy is started without using dk://...
                    $global:modal_box_visible = $true
                }

                # Keep listening for messages in a loop
                Write-Host "Listening for incoming messages..."
                while ($true) {
                    if ($job_finished_count -gt 0) {
                        # Write-Host "Finished $job_finished_count job(s)."
                        ;
                    }

                    # Write-Host $(Get-Date) $job_finished_count
                    
                    if ($websocket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
                        #Write-Host "We intentionally disposed proxy websocket previously.  Restablishing the connection."
                        $websocket.Dispose()
                        Write-Host "Somehow the websocket connection got closed.  Reconnecting..."
                        $websocket = wsfe_proxy_connect -token $token -proxy_ws $proxy_ws -proxy_domain $proxy_domain -verbose $true
                        $websocket = wait_for_proxy_ready -websocket $websocket -token $token -proxy_ws $proxy_ws -proxy_domain $proxy_domain
                        Write-Host "Connection re-established."
                        $connId = $null
                        $last_ping_sent_time = Get-Date 
                    }

                    try {
                        $receiveBuffer = New-Object -TypeName byte[] -ArgumentList 4096
                        $receivedMessage = retrieve_message -websocket $websocket -receiveBuffer $receiveBuffer

                        if ($websocket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
                            Write-Host "Connection closed.  CHECK A.  Continue."
                        }

                        if (@("timeout","exception","closed") -notcontains $receivedMessage) {
                            $receivedJson = $receivedMessage | ConvertFrom-Json
                            $receivedJsonPretty = $receivedJson | ConvertTo-Json -Depth 4
                            # Write-Host "Message received: $receivedJsonPretty"
                            #$receivedJsonPretty >> $debug_file
                            $type = $receivedJson.type 
                            $cmd = $receivedJson.cmd 
                            $connId = $receivedJson.connId

                            $now = Get-Date
                            $last_ping_sent_diff = ($now - $last_ping_sent_time).TotalSeconds
                            if (($null -ne $connId) -and ($last_ping_sent_diff -ge 30)) {
                                Write-Host "Sending ping.  connId:" $connId (Get-Date)
                                send_ping -websocket $websocket -connId $connId
                                $initial_ping_sent = $true 
                                $last_ping_sent_time = Get-Date
                            }
        
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
    
                            if ($job_id -ne $null) {
                                $fileName = "\jobs\$job_id.ps1"
                                $fullPath = Join-Path -Path $working_directory -ChildPath $fileName 
                                $profile_file = Join-Path -Path $working_directory -ChildPath "profile_status.txt" 
                                $error_file = Join-Path -Path $working_directory -ChildPath "error.txt" 

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

                                # We already got the file.  Dispose the websocket connection while we run the job.
                                # $websocket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Closing", [Threading.CancellationToken]::None).Wait()
                                # $websocket.Dispose()  
    
                                #$fullPath >> $debug_file
    
                                #Write-Host "BEFORE RUNNING THE PROGRAM"
                                try {
                                    # $fullPath = "C:\Users\Khai\windk\jobs\d6UiyHciDo2aIs4Wz0Nx.ps1"
                                    Write-Host "Starting job ID: " $job_id
                                    # & $fullPath 2>&1 | Tee-Object -FilePath $debug_file | Out-Default
                                    & $fullPath 1> (Tee-Object -FilePath $debug_file -Append | Out-Default) 2> $error_file
                                    [Console]::Out.Flush()
                                } catch {
                                    #Write-Host "The job encounted an exception: $($_.Exception.Message)" 
                                    $error_stack = $_.Exception.Message + "`n`n" + $_.Exception.StackTrace
                                    $error_stack > $debug_file

                                    # There was an exception thrown, most likely a syntax error.
                                    # Rather than creating a job exec result record, here, we send a 
                                    # PUT request to the job finished endpoint with the extra_info property 
                                    # as part of the request, with the stacktrace as stderr so that 
                                    # the code inside taskservice/src/app.py will as the LLM to fix 
                                    # the problem.  The code inside taskservice/src/app.py does not seem to 
                                    # send the exception or error to the LLM when it invoke the SuggestSaveExecuteTask 
                                    # method for some reason.  It doesn't do that even when there was an 
                                    # exception thrown, it seems.
                                    $job_finished_url = $dagknows_url + '/api/jobs/' + $job_id + '/jobFinished/'
                                    $reqObj = @{}
                                    $reqObj['extra_info'] = @{}
                                    $reqObj['extra_info']['has_issue'] = 'true'
                                    $reqObj['extra_info']['exec_reuslts'] = @{}
                                    $reqObj['extra_info']['exec_reuslts']['stderr'] = $error_stack
                                    $reqObj = $reqObj | ConvertTo-Json
                                    $response = Invoke-RestMethod -Uri $job_finished_url -Method PUT -Headers $headers -Body $reqObj
                                }

                                while ($true) {
                                    $success = $false
                                    try {
                                        Set-Content -Path $profile_file -Value "Job finished."
                                        $success = $true
                                    } catch {
                                        $success = $false
                                    }
                                    if ($success) {
                                        break
                                    } else {
                                        # If we are not able to write to the file because the profile process is reading from it,
                                        # sleep for some time and retry
                                        Start-Sleep -Seconds 1
                                    }
                                }
                                
                                $job_finished_count = $job_finished_count + 1

                                #$task_job = Start-Job -ScriptBlock { & $using:fullPath }
                                #Wait-Job -Job $task_job
                                #Write-Host "AFTER RUNNING THE MAIN JOB"
                                #$output = Receive-Job -Job $task_job
                                #Write-Host $output
                                #Write-Host "Debug file:" $debug_file
                                #"``" >> $debug_file
                                #$output >> $debug_file

                                #Remove-Job -Job $task_job

                                if (-not $global:modal_box_visible) {
                                    #$global:dialog_job = Start-Job -ScriptBlock $dialogScript -ArgumentList $proxy_domain, $runbook_task_id, $token, $current_job_file, $job_id, $user_info, $dagknows_url, $exit_file, $debug_file
                                    $which_button = $dialogScript.Invoke($proxy_domain, $runbook_task_id, $token, $current_job_file, $job_id, $user_info, $dagknows_url, $exit_file, $debug_file)
                                    if ("problem_resolved"  -eq $which_button) {
                                        Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job
                                        Clear-Host
                                        Write-Host "Please close this window if it does not go away by itself."
                                        # Write-Host "Your clicked on (A): " $which_button ".  Exiting."
                                        # Start-Sleep -Seconds 3
                                        $host.SetShouldExit(1)
                                        Remove-Item $exit_file
                                        exit 0
                                    } else {
                                        Clear-Host
                                        Write-Host "For now, please minimize, but do not close this window."
                                        $global:modal_box_visible = $false
                                    }
                                }

                                # $websocket = wsfe_proxy_connect -token $token -proxy_ws $proxy_ws -proxy_domain $proxy_domain -verbose $false

                                if ($job_finished_count -gt 0) {
                                    # Write-Host "Websocket re-established."
                                    ;
                                }
    
                                #$websocket.Dispose()  
                                #break
                            }

                            if ($job_finished_count -gt 0) {
                                # Write-Host "receivedData.SetLength resetted."
                                ;
                            }
                        }

                    } catch {
                        Write-Host "An unexpected error occurred: $_"
                        Write-HOst "Stack trace:" 
                        Write-Host $_.Exception.StackTrace
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
            # The finally block is always invoked, so if we want the proxy to be persistent, do not dispose the websocket.
            # Write-Host "Websocket connection disposed inside the finally block"
            # $websocket.Dispose()
            ;
        }
    }

    #Write-Host "runbook_task_id: $runbook_task_id, proxy_ws: $proxy_ws, proxy_http: $proxy_http, proxy_domain: $proxy_domain, WORKING_DIRECTORY: $working_directory"
    $exit_file = Join-Path -Path $working_directory -ChildPath "exit.txt" 
    # We are using multiple background jobs, and using file to determine when the main process should terminate
    # Before we start, remove the exit file
    if (Test-Path -Path $exit_file) {
        # If the file exists, write "exit_now" to it, and wait for the other process to exit.
        # When the other process see this, it should write "exiting" to this file before exiting.
        $content = Get-Content -Path $exit_file -Raw
        $content = $content.Trim()
        
        #Write-Host "Content: " $content
        if (($content -ne "running") -and ($conent -ne "exiting") -and ($content -ne "exit_now")) {
            #Write-Host "CHECK A.  Content: " $content ", PID: " $PID
            $processInfo = Get-Process -Id $content
            if ($processInfo) {
                #Write-Host "CHECK B"
                #$processInfo | Format-List
                #Write-Host $processInfo
                $process = Get-CimInstance -ClassName Win32_Process | Where-Object { $_.ProcessId -eq $pid }
                if (($process) -and ($process.CommandLine) -and ($process.CommandLine.Contains("winprox"))) {
                    try {
                        Stop-Process -Id $content
                        Remove-Item $exit_file
                    } catch {
                        ;
                    }

                }
            } else {
                # The process that is captured in the exit file already terminated somehow.
                ;
            }
        }
    }
    Set-Content -Path "$exit_file" -Value $PID
    # if (($null -ne $runbook_task_id) -and ($runbook_task_id -ne "")) {
    #     Write-Host "RUN BOOK ID PROVIDED"
    # } else {
    #     Write-Host "RUN BOOK ID NOT PROVIDED"
    # }

    Start-WebSocketListener -runbook_task_id $runbook_task_id -proxy_ws $proxy_ws -proxy_http $proxy_http -proxy_domain $proxy_domain -token $token -working_directory $working_directory -exit_file $exit_file
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
