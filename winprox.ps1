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

$dialogScript = {
    param($proxy_ws, $proxy_domain, $runbook_task_id, $token, $current_job_file, $job_id)
    # Use a suitable dialog method, like a custom function or a .NET dialog
    Add-Type -AssemblyName System.Windows.Forms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.Width = 470
    $form.Height = 150
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.TopMost = $true

    # Create a Label to display the message
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Starting."
    #$label.Text = $global:dialog_message
    $label.AutoSize = $true
    $label.Top = 30
    $label.Left = 50
    $form.Controls.Add($label)

    # Optional: Add a button to close the form

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $content = ""
    $problemResolvedBtn 
    $problemResolvedBtn = New-Object System.Windows.Forms.Button
    $problemResolvedBtn.Text = "Problem resolved"
    $problemResolvedBtn.Top = 70
    $problemResolvedBtn.Left = 70
    $problemResolvedBtn.Width = 150
    $problemResolvedBtn.Add_Click({ 
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
        Write-Host "Ticket created."  # Placeholder for ticket creation logic
        $label.Text = "Ticket created."
        $timer.Stop()
        $problemResolvedBtn.Text = "OK"
        $problemNotResolvedButton.Visible = $false
        $problemNotResolvedButton.Hide()
        $form.Controls.Remove($problemNotResolvedButton)
        $problemNotResolvedButton.Dispose()
        #$form.Hide()
        $form.Invalidate()
        $form.Update()
        $form.Refresh()
        #$form.Close()
        #$host.SetShouldExit(1)
    })
    $problemNotResolvedButtonVisible = $false 

    $timer.Add_Tick({
        $content = Get-Content -Path $current_job_file -Raw
        $label.Text = $content

        if (($content.StartsWith("Ticket")) -or ($content.StartsWith("Runbook finished"))) {
            if (-not $problemResolvedButtonVisible) {
                $form.Controls.Add($problemResolvedBtn)
                $problemResolvedButtonVisible = $true
            }

            if (-not $problemNotResolvedButtonVisible) {
                $form.Controls.Add($problemNotResolvedButton)
            }
        }
    
    })

    $form.Add_Shown({ $timer.Start() })
    $form.Add_FormClosed({ $timer.Stop() })

    # Show the form
    $form.ShowDialog() | Out-Null
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
            [string]$working_directory
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
            Write-Host "Really trying"
            $websocket.ConnectAsync($uri, [Threading.CancellationToken]::None).Wait()
            Write-Host "Done waiting"

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
                Write-Host "Making a POST request"
                Write-Host "URL: " $apiUrl
                Write-Host "Headers: " $headers
                Write-Host "Body: " $jsonBody
                $response = Invoke-RestMethod -Uri $apiUrl -Method POST -Headers $headers -Body $jsonBody
                Write-Host ($response | ConvertTo-Json -Depth 4)

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
                        #$receivedJsonPretty >> "debug.txt"
                        $user_info = $receivedJson.message.user_info
                        $conv_id = $receivedJson.message.req.req_obj.conv_id
                        $iter = $receivedJson.message.req.req_obj.iter
                        $code_lines = $receivedJson.message.req.req_obj.code
                        $job_id = $receivedJson.message.req.job_id
                        $role_token = $receivedJson.token
                        $runbook_task_id = $receivedJson.message.req.req_obj.runbook_task_id
                        $starting_child_path = $receivedJson.message.req.req_obj.starting_child_path
                        $task_id = $receivedJson.message.req.req_obj.task_id


                        Ensure-DirectoryExists -directoryPath ".\jobs"

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

                            #Set-Content -Path $current_job_file -Value "Starting..."
                            if (-not $global:modal_box_visible) {
                                Start-Job -ScriptBlock $dialogScript -ArgumentList $proxy_ws, $proxy_domain, $runbook_task_id, $token, $current_job_file
                                $global:modal_box_visible = $true
                            }

                            & $fullPath  

                            # At this point, the job is technically finished.  If the last task in the runbook created a ticket
                            # we simply want to display that ticket.  Otherwise, we want to write a message to the current_job.txt 
                            # file so that base on the content of this file, the dialog box can display appropriate buttons.
                            $content = Get-Content -Path $current_job_file -Raw
                            if (! $content.StartsWith("Ticket")) {
                                Set-Content -Path $current_job_file -Value "Runbook finished.  Please check if the problem has been resolved."
                            }
                            #$websocket.Dispose()  
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
            $websocket.Dispose()
        }
    }

    #Write-Host "runbook_task_id: $runbook_task_id, proxy_ws: $proxy_ws, proxy_http: $proxy_http, proxy_domain: $proxy_domain, WORKING_DIRECTORY: $working_directory"
    Start-WebSocketListener -runbook_task_id $runbook_task_id -proxy_ws $proxy_ws -proxy_http $proxy_http -proxy_domain $proxy_domain -token $token -working_directory $working_directory
}

$token = $Env:PROXY_TOKEN
$proxy_domain = $Env:PROXY_DOMAIN

$proxy_secure = [System.Boolean]::Parse($Env:PROXY_SECURE)
Write-Host "proxy_secure: " $proxy_secure
$proxy_ws = "ws://"
$proxy_http = "http://"
if ($proxy_secure) {
    $proxy_ws = "wss://"
    $proxy_http = "https://"
}

$global:modal_box_visible = $false
$proxy_block.Invoke($runbook_task_id, $proxy_ws, $proxy_http, $proxy_domain, $token, $PSScriptRoot)


