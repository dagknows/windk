$scheme = "dk"  # Replace with your desired scheme name
$scriptPath = "C:\Users\Administrator\windk\winprox.ps1"  # Replace with the path to your PowerShell script

# Define registry path for the custom scheme
$regPath = "Registry::HKEY_CLASSES_ROOT\$scheme"
New-Item -Path $regPath -Force | Out-Null
Set-ItemProperty -Path $regPath -Name "(Default)" -Value "URL:$scheme Protocol"
Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value ""

# Create the command to execute PowerShell with the script
$commandPath = "$regPath\shell\open\command"
New-Item -Path $commandPath -Force | Out-Null
Set-ItemProperty -Path $commandPath -Name "(Default)" -Value "powershell.exe -ExecutionPolicy Bypass -File `"$scriptPath`" `"%1`""
