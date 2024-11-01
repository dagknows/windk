param (
    [string]$url
)
$url = $url -replace "^dk://", "https://"

Write-Output "Received URL: $url"
if (-not [string]::IsNullOrEmpty($string)) {
    Start-Process $url
}

# Define your Bearer token
# $token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJkYWdrbm93cy5jb20iLCJzdWIiOiJzYXJhbmdAZGFna25vd3MuY29tIiwibmJmIjoxNzMwMDkwNzE4LCJleHAiOjE3NjE2MjY4OTgsImp0aSI6Imd2U2I2U21iU2FSUzR6RlYiLCJhdWQiOiJkYWdrbm93cyIsInJvbGUiOiJzdXByZW1vIiwidXNlcl9jbGFpbXMiOnsidWlkIjoiMSIsInVuYW1lIjoic2FyYW5nQGRhZ2tub3dzLmNvbSIsIm9yZyI6ImRhZ2tub3dzIiwiZmlyc3RfbmFtZSI6IlNhcmFuZyIsImxhc3RfbmFtZSI6IkRoYXJtYXB1cmlrYXIiLCJyb2xlIjoiU3VwcmVtbyIsImFlc19rZXkiOiIxLVxuTURCTEMtOEx0ZkF1cm9sOUNHMExcbmZLTEIzclxudSIsIm9mc3QiOlszMTQsNDI2LDkxLDEzNCw0MjAsNDI0LDI3NywxOTcsNDQ5LDMzNiw0MzgsMzQ1LDMwMSw0MDUsMTAyLDE4OSwxNTksMTc0LDQwNiw2NiwzMDgsMzc0LDQzOCw0MjUsMTg1LDY1LDI3Nyw5MCwyMDAsMzg0LDIyMSwxMTZdfX0.hm2QvlTSsHslkrT9Db0lEZcs_qcrm2xkGp_pXahuYLfnhuYSfUkc7GeoynoKX2J37DJPaEglNKkEaJKL4rbxlX7kPVHD6ElKc8Se_csNOAHzTQf4h013be-uAaeC2Uo7Pb4ZO5uwquHi2Jqz0LbdtWOtlCFjIjOGugLK26rChJjFfqVLERYsgOXjaTwVqOGUfhT-OFJDaoBbHZAmrIB-UkkMKdIBKcto0DwQSOeyj4nv69htrLrGUheuHQkfE9gEKlaqWyynzx0MZIStjPkPheMzbk-AajrDO5GbaCh46AZEs_zl2_kq1OcgyC0QFrL2Wm5wsQ_gt7XhsMyMbvkOgQ"
$token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJkYWdrbm93cy5jb20iLCJzdWIiOiJraGFpQGRhZ2tub3dzLmNvbSIsIm5iZiI6MTczMDI0MjE4OSwiZXhwIjoxNzYxNzc4MzY5LCJqdGkiOiJJcGZMcGgyZElUZnpMMzVlIiwiYXVkIjoiZGFna25vd3MiLCJyb2xlIjoic3VwcmVtbyIsInVzZXJfY2xhaW1zIjp7InVpZCI6IjEiLCJ1bmFtZSI6ImtoYWlAZGFna25vd3MuY29tIiwib3JnIjoiRGFnS25vd3MiLCJmaXJzdF9uYW1lIjoiS2hhaSIsImxhc3RfbmFtZSI6IkRvYW4iLCJyb2xlIjoiU3VwcmVtbyIsImFlc19rZXkiOiJPRVcrR1RWLTRyZzI5OVByb28tQVFrdUFJT25Jc2h5QSIsIm9mc3QiOlsyODcsMTQ4LDE2OSw4NCwzMzYsMjY1LDE1MSw0MjksMzY1LDE1MCw2NCwzNzAsMTIzLDc3LDIxOSwxNTAsNzEsMjU0LDQ0OCwxNzksMzA2LDEyNCwxMzAsMzMyLDIwNiwyODcsMjExLDQzOSwzMDgsMjUzLDMzOCw2N119fQ.oCM4trdp6sygL0mW3fBQcYib31AdylP-rhJNhdcHOrzdnAa4JcqxR-i5TYiP1CwyhpWAW1mwnZgt3gZPyIOMbbpe_si-cAvDruS_6m-vkeX6NDcq0457dBIohwmU53nk5_kTdokfPh_CKI7jDjCLk409aLcOFlGvRaixjO1xD9iD8xsDMkjMyhENchOLfFCOtXuiFS_GMKATJYLENaRi8gW0X2ula2jh1_lXpO0xeqSKK4pJwH49DJE26xyaYLj9olFEtQ5qFtm54a5wWbSxn35_BalH_M7iO_UhastgEOI9sYoxMMALRBPG6OriqRDzcMjHGuEpi8gBVM1coFt5HQ"

# Define the WebSocket server URI (ensure it starts with wss:// for a secure connection)
# $uri = [System.Uri]::new("wss://dev.dagknows.com/wsfe/proxies/agents/connect")
$uri = [System.Uri]::new("ws://khai.dagknows.com/wsfe/proxies/agents/connect")

$execs_url = "ws://khai.dagknows.com/wsfe"
$dagknows_url = "http://khai.dagknows.com"

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
                $fileName = "$job_id.ps1"
                if ($fileName -ne ".ps1") {
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


