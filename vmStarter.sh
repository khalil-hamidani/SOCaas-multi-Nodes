#this script is to virsh start all the vms 


# running k8s-master 
virsh start k8s-master

# running k8s-worker1
virsh start k8s-worker1

# running k8s-worker2
virsh start k8s-worker2

# pinging the nodes to check if they are up and running
virsh list --all
ls -lh /srv/socaas/libvirt/images/*.qcow2
ping -c 2 192.168.122.10
ping -c 2 192.168.122.11
ping -c 2 192.168.122.12
