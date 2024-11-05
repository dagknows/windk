param (
    [string]$url
)
$url = $url -replace "^dk://", "https://"

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

function ShowPopUpMsg {
    # Load the required assembly
    Add-Type -AssemblyName System.Windows.Forms

    # Create a new form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Pop-up"
    $form.Width = 300
    $form.Height = 150

    # Create a label to display messages
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "This is the first line."
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(10, 20)

    # Add the label to the form
    $form.Controls.Add($label)

    # Show the form
    $form.Show()

    # Pause for 2 seconds before updating the text (simulates a delay)
    Start-Sleep -Seconds 2

    # Append another line to the label's text
    $label.Text += "`nThis is the second line."

    # Create an OK button
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(100, 70)
    $okButton.Add_Click({ $form.Close() }) # Close the form when OK is clicked

    # Add the button to the form after updating the text
    $form.Controls.Add($okButton)

    # Display the form and keep it open until OK is clicked
    $form.ShowDialog()

}

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
        [string]$runbook_task_id
    )

    # Define your Bearer token
    $token = $Env:PROXY_TOKEN
    $proxy_domain = $Env:PROXY_DOMAIN


    # Define the WebSocket server URI (ensure it starts with wss:// for a secure connection)
    # $uri = [System.Uri]::new("wss://dev.dagknows.com/wsfe/proxies/agents/connect")
    $websocket = New-Object System.Net.WebSockets.ClientWebSocket
    $websocket.Options.SetRequestHeader("Authorization", "Bearer $token")
    $uri = [System.Uri]::new("ws://" + $proxy_domain + "/wsfe/proxies/agents/connect")
    $execs_url = "ws://" + $proxy_domain + "/wsfe"
    $dagknows_url = "http://" + $proxy_domain
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
                    $receivedJsonPretty >> "khaidebug.txt"
                    $user_info = $receivedJson.message.user_info
                    $conv_id = $receivedJson.message.req.req_obj.conv_id
                    $iter = $receivedJson.message.req.req_obj.iter
                    $code_lines = $receivedJson.message.req.req_obj.code
                    $job_id = $receivedJson.message.req.job_id
                    $role_token = $receivedJson.token
                    $runbook_task_id = $receivedJson.message.req.req_obj.runbook_task_id
                    $starting_child_path = $receivedJson.message.req.req_obj.starting_child_path
                    $task_id = $receivedJson.message.req.req_obj.task_id

                    Ensure-DirectoryExists -directoryPath ".\.jobs"

                    $fileName = "\.jobs\$job_id.ps1"
                    if ($job_id -ne $null) {
                        $fullPath = Join-Path -Path $PSScriptRoot -ChildPath $fileName 
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

                        & $fullPath    
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
        Write-Error "An error occurred: $_"
    }
    finally {
        # Dispose of the WebSocket instance
        $websocket.Dispose()
    }
}


Start-WebSocketListener -runbook_task_id $runbook_task_id