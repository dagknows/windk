# We want to profile by launching a browser with appropriate URL, but then it may be challenging to response to 
# that dialog.  For that reason, we do not use that approach.  Instead, we require the user to separately start 
# the proxy without providing the URL.  The expectation is that the user starts winprox in one terminal window,
# and open another terminal window to run this script.  These windows should be opened side by side, and the user 
# should watch the output on both windows at the same time.  
# Because, inside winprox, we want to capture the output of the job and send it to the debug file for debugging 
# purpose anyway, we should be able to tail the debug file for changes, and detect stuckness using the debug file 
# some how, if the content is not changed within a reasonable amount of time.
# There seems to be some issue with writing to the debug file (the debug file seems to be empty when the job is 
# finished, but the "job finished" message is still displayed on the screen fine).  I cannot see where this 
# is coming from.  For this reason, I switch to using the profile_status.txt file.

$profile_block = {
    param (
        [string]$runbook_task_id,
        [string]$proxy_ws,
        [string]$proxy_http,
        [string]$proxy_domain,
        [string]$token,
        [string]$working_directory,
        [int]$limit
    )

    function submit_job_for_runbook {
        param (
            [string]$runbook_task_id,
            [string]$proxy_ws,
            [string]$proxy_http,
            [string]$proxy_domain,
            [string]$token,
            [string]$working_directory
        )
        $params = @{} # These jobs typically do not take parameters.  If they do, we need to parse these parameters from the URL somehow.

        # Now make a request.
        $dagknows_url = $proxy_http + $proxy_domain
        $apiUrl = $dagknows_url + "/api/tasks/" + $runbook_task_id + "/execute"

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
        $response = Invoke-RestMethod -Uri $apiUrl -Method POST -Headers $headers -Body $jsonBody
        return ""
    }

    function Start-Profiling {
        param (
            [string]$runbook_task_id,
            [string]$proxy_ws,
            [string]$proxy_http,
            [string]$proxy_domain,
            [string]$token,
            [string]$working_directory,
            [int]$limit
        )

        $profile_file = Join-Path -Path $working_directory -ChildPath "profile_status.txt" 

        for ($i = 1; $i -le $limit; $i++) {
            # Before submitting a new job, clear out the content of the profile file from this side.
            # This should "re-initialize" the last updated timestamp on this file as well.
            Set-Content -Path $profile_file -Value " "
            Write-Host "Starting iteration " $i " at " (Get-Date)
            submit_job_for_runbook -runbook_task_id $runbook_task_id -proxy_ws $proxy_ws -proxy_http $proxy_http -proxy_domain $proxy_domain -token $token -working_directory $working_directory -exit_file $exit_file
            Write-Host "Waiting for some time for the proxy to get started."
            Start-Sleep -Seconds 2
            try {
                $lastUpdatedTime = (Get-Item $profile_file).LastWriteTime
                $currentTime = Get-Date
                $timeDifferenceInSeconds = ($currentTime - $lastUpdatedTime).TotalSeconds
    
                if ($timeDifferenceInSeconds -gt 300) {
                    Write-Host "Stuckness detected.  CHECK A."
                    exit 1
                }    
            } catch {
                $exception_message = $_.Exception.Message + "`n" + $_.Exception.StackTrace
                Write-Host "Exception  CHECK A.  Message: " $exception_message
            }

            Write-Host "Waiting for the current job to finish."
            $currentTime1 = Get-Date
            while ($true) {
                try {
                    $currentTime2 = Get-Date
                    $timeDifferenceInSeconds = ($currentTime2 - $currentTime1).TotalSeconds
                    if ($timeDifferenceInSeconds -gt 600) {
                        # For the job that we selected to use for detecting stuckness or detecting other issues, 
                        # if it takes longer than 10 minutes, there is probably something wrong.  If that job naturally 
                        # take longer than 10 minutes to run, do not use it for this script.  Pick some other runbook 
                        # instead.
                        Write-Host "Stuckness detected.  CHECK B."
                        exit 2
                    }
                    $fileContent = Get-Content -Path $profile_file -Raw
                    if (($null -ne $fileContent) -and ($fileContent.Contains("Job finished"))) {
                        break;
                    }
                    Start-Sleep -Seconds 1    
                } catch {
                    $exception_message = $_.Exception.Message + "`n" + $_.Exception.StackTrace
                    Write-Host "Exception  CHECK B.  Message: " $exception_message    
                }
            }
        }

        Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job
        Get-Job | Where-Object { $_.State -eq 'Completed' } | Remove-Job

    }

    Start-Profiling -runbook_task_id $runbook_task_id -proxy_ws $proxy_ws -proxy_http $proxy_http -proxy_domain $proxy_domain -token $token -working_directory $working_directory -exit_file $exit_file -limit $limit

}

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

$runbook_task_id = Read-Host "Please provide the ID of the runbook to use"
$limit = [int](Read-Host "How many iteration should I run this for?")
Read-Host "It is expected that the proxy is already started.  If not, please start it now, hit enter key when the proxy is fully started."
$profile_block.Invoke($runbook_task_id, $proxy_ws, $proxy_http, $proxy_domain, $token, $PSScriptRoot, $limit)
Clear-Host 
Write-Host "All " $limit " iteration(s) processed successfully.  Did not face any stuck connection issue."
exit 0