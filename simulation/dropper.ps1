# SOCaaS Malware Dropper Simulation
# Creates files with known malicious hashes that VirusTotal detects

$mdir = "$env:APPDATA\MicrosoftEdge"
Remove-Item -Recurse -Force $mdir -ErrorAction SilentlyContinue
mkdir $mdir -Force | Out-Null
attrib +h $mdir

# === 1. EICAR test file (world-famous VirusTotal hash) ===
# SHA256: 275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f
# MD5: 44d88612fea8a8f36de82e1278abb02f
$eicar = 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
Set-Content -Path "$mdir\update_helper.exe" -Value $eicar

# === 2. Fake meterpreter PE payload ===
$meterpreter = @'
MZ\x90\x00\x03\x00\x00\x00\x04\x00\x00\x00\xff\xff\x00\x00\xb8\x00\x00\x00
This program cannot be run in DOS mode.
SOCaaS_METERPRETER_REVERSE_TCP
LHOST=10.0.0.99 LPORT=4444
C2_BEACON=evil-c2-malware.ddns.net
ENCRYPTED_PAYLOAD=base64_encoded_data_here
'@
Set-Content -Path "$mdir\MicrosoftEdgeUpdate.exe" -Value $meterpreter

# === 3. C2 beacon exfiltration data ===
$beacon = @"
HOST=$env:COMPUTERNAME
USER=$env:USERNAME
C2_SERVER=evil-c2.ddns.net:4444
EXFILTRATION_PATH=$mdir\sysinfo.dat
TIMESTAMP=$(Get-Date -Format o)
CREDENTIALS_CAPTURED=yes
"@
Set-Content -Path "$mdir\c2_beacon.dat" -Value $beacon

# === 4. Registry persistence ===
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty -Path $regPath -Name "EdgeUpdateCheck" -Value "$mdir\MicrosoftEdgeUpdate.exe" -Force

# === 5. Also drop in Downloads for double detection ===
Set-Content -Path "$env:USERPROFILE\Downloads\ChatGPTPro_Setup.exe" -Value $eicar

Write-Host "=== DROPPER DEPLOYED ==="
Write-Host "Files in: $mdir"
Get-ChildItem $mdir | ForEach-Object { Write-Host "  $($_.Name)  $($_.Length) bytes" }
