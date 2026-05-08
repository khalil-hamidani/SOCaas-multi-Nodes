#!/usr/bin/env bash
# Persist Docker TCP listener for Shuffle Orborus worker communication.
# Run on the SOAR worker node (k8s-worker2).
#
# This script:
# 1. Creates a systemd override so dockerd listens on 0.0.0.0:2375
# 2. Reloads systemd and restarts Docker
# 3. DOCKER_HOST is set in the Helm chart (values-multinode.yaml) to
#    tcp://192.168.122.12:2375
# 4. The NetworkPolicy template allows egress to Docker TCP (port 2375)
#    from SOAR pods.

set -euo pipefail

DOCKER_HOST_IP="${1:-192.168.122.12}"

echo "[*] Configuring Docker TCP listener on ${DOCKER_HOST_IP}:2375"

sudo mkdir -p /etc/systemd/system/docker.service.d

sudo tee /etc/systemd/system/docker.service.d/override.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375 --containerd=/run/containerd/containerd.sock
EOF

echo "[*] Restarting Docker..."
sudo systemctl daemon-reload
sudo systemctl restart docker

sleep 3
sudo systemctl status docker --no-pager | head -5

echo "[*] Docker TCP listener configured successfully."
echo "[*] Verify with: curl -s http://${DOCKER_HOST_IP}:2375/version"
