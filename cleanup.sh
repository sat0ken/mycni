#!/bin/bash
apt update
apt install -y bridge-utils iptables iproute2
ip link set br0 down
brctl delbr br0
rm -f /etc/cni/net.d/mycni.conf
rm -f /opt/cni/bin/mycni
ip link show | grep ": veth_host" | cut -d"@" -f1 | cut -d":" -f2 | xargs -I dev ip link del dev
iptables -t filter -nvL --line-numbers | grep 10.244 | grep -o "^[0-9]" | head -n 1 | xargs -I num iptables -t filter -D FORWARD num
iptables -t nat -nvL --line-numbers | grep br0 | grep -o "^[0-9]" | xargs -I num iptables -t nat -D POSTROUTING num
echo "mycni cleanup successfully..."
