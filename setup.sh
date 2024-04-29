#!/bin/bash
apt update
apt install -y curl iproute2 jq bridge-utils iptables
curl -LO "https://dl.k8s.io/release/$(curl -LS https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl && mv ./kubectl /usr/local/bin

# NodeのspecからCIDRを取得
podCIDR=$(kubectl get node $(hostname) -o jsonpath='{.spec.podCIDR}')
printf "%s podCIDR is %s\n" $(hostname) $podCIDR

# linux-bridgeにセットするIPを生成
bridge_ip=$(echo $podCIDR | sed -e "s|0/24|1/24|")

# linux-bridgeを作成してIPアドレスを設定
brctl addbr br0
ip link set br0 up
ip addr add $bridge_ip dev br0
printf "create br0, set ipaddr %s\n" $bridge_ip

# 外に出れるようにiptablesを設定
cluster_cidr=$(echo $bridge_ip | sed -e "s/10.244.*/10.244.0.0\/16/")
iptables -A FORWARD -s $cluster_cidr -j ACCEPT
iptables -A FORWARD -d $cluster_cidr -j ACCEPT
iptables -t nat -N KIND-MASQ-AGENT
iptables -t nat -A POSTROUTING -m addrtype ! --dst-type LOCAL -j KIND-MASQ-AGENT
iptables -t nat -A KIND-MASQ-AGENT -d $cluster_cidr -j RETURN
iptables -t nat -A KIND-MASQ-AGENT -j MASQUERADE

# 他のNodeのIPアドレスとPodCIDRを取得してip routeコマンドで静的ルートを設定
nodes=($(kubectl get node -o json | jq .items | jq --arg arg $(hostname) -r '.[] | select(.metadata.name != $arg) .metadata.name'))
for node in "${nodes[@]}"
do
  node_ip=$(kubectl get node "${node}" -o jsonpath='{.status.addresses}' | jq -r '.[] | select(.type == "InternalIP") .address')
  pod_cidr=$(kubectl get node "${node}" -o jsonpath='{.spec.podCIDR}')
  printf "ip route add %s via %s dev eth0\n" $pod_cidr $node_ip
  ip route add $pod_cidr via $node_ip dev eth0
done
curl -LO https://raw.githubusercontent.com/sat0ken/mycni/master/mycni.conf && mv ./mycni.conf /etc/cni/net.d
curl -LO https://raw.githubusercontent.com/sat0ken/mycni/master/mycni && chmod +x ./mycni && mv ./mycni /opt/cni/bin
echo "mycni init successfully..."
