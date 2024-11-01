
param (
    [string]$url
)
$url = $url -replace "^dk://", "https://"

Write-Output "Received URL: $url"
if (-not [string]::IsNullOrEmpty($string)) {
    Start-Process $url
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


# Define your Bearer token
$token = $Env:PROXY_TOKEN
$proxy_domain = $Env:PROXY_DOMAIN


# Define the WebSocket server URI (ensure it starts with wss:// for a secure connection)
# $uri = [System.Uri]::new("wss://dev.dagknows.com/wsfe/proxies/agents/connect")
$uri = [System.Uri]::new("ws://" + $proxy_domain + "/wsfe/proxies/agents/connect")
$execs_url = "ws://" + $proxy_domain + "/wsfe"
$dagknows_url = "http://" + $proxy_domain

# Create a new ClientWebSocket instance
$websocket = New-Object System.Net.WebSockets.ClientWebSocket

# Add the Authorization header with the Bearer token
$websocket.Options.SetRequestHeader("Authorization", "Bearer $token")

# (Optional) Bypass SSL certificate validation (not recommended for production)
# [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

Write-Host "Trying to connect to wss"

try {
    # Connect to the WebSocket server
    Write-Host "Really trying"
    $websocket.ConnectAsync($uri, [Threading.CancellationToken]::None).Wait()
    Write-Host "Done waiting"

    if ($websocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        Write-Host "WebSocket connection established. Listening for incoming messages..."

        # Keep listening for messages in a loop
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
                #Write-Host "Message received: $receivedJsonPretty"
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

                # & $fullPath p.iterid, p.convid, string(user_info), p.token
                # Write-Host $job_id
                # Write-Host $code_lines
                Ensure-DirectoryExists -directoryPath ".\.jobs"

                $fileName = "\.jobs\$job_id.ps1"
                if ($job_id -ne $null) {
                    # $iter $conv_id $token
                    $fullPath = Join-Path -Path $PSScriptRoot -ChildPath $fileName 
                    $streamWriter = [System.IO.StreamWriter]::new($fullPath, $false, [System.Text.Encoding]::UTF8)
                    $final_execs_url = $execs_url 
                    # outfile.writeln(f"$global:ALLTASKS = '{taskcache_jsonstr}' | ConvertFrom-Json ")
                    $other_info =    '$conv_id = "' + $conv_id + '"' + "`n" +
                                '$iter = "' + $iter + '"' + "`n" +
                                '$token = "' + $role_token + '"' + "`n" +
                                '$execs_url = "' + $final_execs_url + '"' + "`n" +
                                '$global:dagknows_url = "' + $dagknows_url + '"' + "`n" + 
                                '$user_info = ' + "'" + ($user_info | ConvertTo-Json -Compress) + "'" + "`n" + 
                                '$user_info = ' + 'ConvertTo-Hashtable($user_info | ConvertFrom-Json)' + "`n"
                    # Loop through each line in $code_lines and write it to the file
                    foreach ($line in $code_lines) {

                        if ($line.Contains("DK_OTHER_INFO")) {
                            $streamWriter.WriteLine($other_info)
                        } else {
                            $streamWriter.WriteLine($line)
                        }

                    }

                    # Close the StreamWriter to save the file
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


