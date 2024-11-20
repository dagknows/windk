$token = $Env:PROXY_TOKEN
$proxy_domain = $Env:PROXY_DOMAIN
$proxy_secure = $Env:PROXY_SECURE.Trim().ToLower().Trim("'").Trim('"')

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
$uri = [System.Uri]::new($proxy_ws + $proxy_domain + "/wsfe/proxies/agents/connect")
Write-Host "URI: " $uri  

$websocket = New-Object System.Net.WebSockets.ClientWebSocket
$websocket.Options.SetRequestHeader("Authorization", "Bearer $token")

# try {
#     Write-Host "Trying to create websocket"
#     $websocket.ConnectAsync($uri, [Threading.CancellationToken]::None).Wait()
#     if ($websocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
#         Write-Host "Able to connect to websocket"
#     }
# } catch {
#     $errored = $true
#     Write-Host "Error: $($_.Exception.Message)"
#     Write-Host "URI: " $uri
#     #Write-Host "StackTrace: $($_.Exception.StackTrace)"
#     Write-Host "Unable to establish websocket connection."
# }

$itercount = 0
while ($itercount -lt 50) {
    $errored = $false
    try {
        Write-Host "Trying to create websocket"
        $websocket = New-Object System.Net.WebSockets.ClientWebSocket
        $websocket.Options.SetRequestHeader("Authorization", "Bearer $token")
        $websocket.ConnectAsync($uri, [Threading.CancellationToken]::None).Wait()
    } catch {
        $errored = $true
        Write-Host "Error: $($_.Exception.Message)"
        Write-Host "URI: " $uri
        #Write-Host "StackTrace: $($_.Exception.StackTrace)"
        Write-Host "Unable to establish websocket connection.  Check A.  Trying again."
    }

    if ($websocket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        $errored = $true
    } else {
        Write-Host "Able to connect.  itercount: " $itercount
    }

    Write-Host "The value of errored:" $errored
    Start-Sleep -Seconds 2
    Write-Host "Done sleeping for 2 seconds"
    $itercount = $itercount + 1
}    

