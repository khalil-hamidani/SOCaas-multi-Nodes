#!/bin/bash
VM_NAME="${1:?Usage: wait_for_vm_ip.sh <vm_name>}"
for i in $(seq 1 36); do
  IP=$(virsh domifaddr "$VM_NAME" --source agent 2>/dev/null | grep -oP '192\.168\.200\.\d+' | head -1 || true)
  if [ -z "$IP" ]; then
    IP=$(cat /var/lib/libvirt/dnsmasq/virbr-sandbox.status 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); [print(x['ip-address']) for x in d]" 2>/dev/null)
  fi
  if [ -n "$IP" ]; then echo "$IP"; exit 0; fi
  sleep 5
done
exit 1
