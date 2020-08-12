#!/bin/bash

yum install -y bridge-utils jq
mkdir -p /var/run/netns

brctl addbr br0
ip link set br0 up
ip addr add 10.244.0.1/24 dev br0

iptables -A FORWARD -s 10.244.0.0/16 -j ACCEPT
iptables -A FORWARD -d 10.244.0.0/16 -j ACCEPT

iptables -t nat -A POSTROUTING -s 10.244.0.0/24 ! -o br0 -j MASQUERADE

ip route add 10.244.1.0/24 via 192.168.0.100 dev eth0
ip route add 10.244.2.0/24 via 192.168.0.101 dev eth0
