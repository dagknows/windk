$script_path = Read-Host "Please provide the complete path for your code"
$runbook_task_id = Read-Host "Please provide the runbook task ID"

$folderPath = Split-Path -Path $script_path
$iconPath = Join-Path -Path $folderPath -ChildPath "dagknows-for-windows.ico"
# $iconPath = Join-Path -Path $folderPath -ChildPath "dagknows-windows-transparent-256.ico"
$desktop = [Environment]::GetFolderPath('Desktop')

# Define the shortcut path and name
$shortcutPath = Join-Path -Path $desktop -ChildPath "Dagknows Troubleshooting.lnk"

# Create a new COM object for the WScript.Shell
$wshShell = New-Object -ComObject WScript.Shell

# Create the shortcut object
$shortcut = $wshShell.CreateShortcut($shortcutPath)
# Set the shortcut properties
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$script_path`" -desktop true -runbook_task_id $runbook_task_id"
$shortcut.WorkingDirectory = (Get-Location).Path
$shortcut.IconLocation = $iconPath
$shortcut.Save()

Write-Host "Shortcut created at $shortcutPath.  Please check."
