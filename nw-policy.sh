#!/bin/bash

# ipsetを作成しPodのIPを登録する
set_ipset_rules() {
	local ipset_name=$1
	shift
	local set_ip_list=($@)

	stdout=$(sudo ipset list | grep $ipset_name)
	if [ -z "$stdout" ]; then
		printf "ipset create %s hash:ip\n" $ipset_name >> cmd.txt
		for pod_ip in "${set_ip_list[@]}"
		do
			printf "ipset add %s %s\n" $ipset_name $pod_ip >> cmd.txt
		done
	else
		# 更新処理をすべきだがあとで考える
		:
	fi
}

set_ingress_nw_policy_peer() {
	spec=$1
	nw_policy_peers=$2
	name=$(echo "$item" | jq -r .metadata.name)
	namespace=$(echo "$spec" | jq -r .metadata.namespace)
	allow_ipset_name=$(printf "%s-%s" $namespace $name)

	for peer in "${nw_policy_peers[@]}"
	do
		if [ $peer = "ipBlock" ]; then
			echo "ipBlock";
		elif [ $peer = "namespaceSelector" ]; then
			echo "namespaceSelector";
		else
			allow_pod_label=$(echo "$spec" | jq -c '.spec.ingress[].from[].podSelector.matchLabels' | sed -e "s/{//" -e "s/}//" -e "s/\"//g" -e "s/:/=/")
			allow_pod_ips=($(kubectl -n $namespace get pod -l $allow_pod_label -o json | jq -r .items[].status.podIP))
			allow_ipset_name+="-from-podSelector"
			set_ipset_rules $allow_ipset_name "${allow_pod_ips[*]}"
		fi
	done

	# 作成したipsetの名前を戻り値として返す
	echo $allow_ipset_name
}

set_ingress() {
	ingress_list=($(echo "$1" | jq -r '.spec.ingress[] | keys | .[]'))
	local allow_ipset_name

	for ingress in "${ingress_list[@]}"
	do
		if [ $ingress = "from" ]; then
			from=($(echo "$1" | jq -r .spec.ingress[] | jq -r '.from[] | keys | .[]'))
			allow_ipset_name=$(set_ingress_nw_policy_peer $1 $from)
		else
			# Todo: portsの処理
			:
		fi
	done

	# 作成したipsetの名前を戻り値として返す
	echo $allow_ipset_name
}

FILE=cmd.txt
if [ -f "$FILE" ]; then
    rm $FILE
fi

# mainの処理
kubectl get networkpolicies.networking.k8s.io -A -o json | jq -c .items[] | while read -r item; do
    name=$(echo "$item" | jq -r .metadata.name)
	namespace=$(echo "$item" | jq -r .metadata.namespace)
	policy_types=($(echo "$item" | jq -r .spec.policyTypes[]))
	pod_labels=$(echo "$item" | jq -c '.spec.podSelector.matchLabels' | sed -e "s/{//" -e "s/}//" -e "s/\"//g" -e "s/:/=/")
	pod_ips=($(kubectl -n $namespace get pod -l $pod_labels -o json | jq -r .items[].status.podIP))

	# NW Polocyを設定する対象のPodのipsetを作成する
	target_ipset_name=$(printf "%s-%s-target" $namespace $name)
	set_ipset_rules $target_ipset_name "${pod_ips[*]}"

	for policy in "${policy_types[@]}"
	do
		if [ $policy = "Ingress" ]; then
			allow_ipset_name=$(set_ingress $item)
			printf "iptables -A INPUT --ipv4 -m set --set %s src -m set --set %s dst -j ACCEPT\n" $allow_ipset_name $target_ipset_name >> cmd.txt
			printf "iptables -A INPUT -m set ! --set %s src -m set --set %s dst -j DROP\n" $allow_ipset_name $target_ipset_name >> cmd.txt
		else
			:
		fi
	done
done
