#!/bin/bash

set_ingress_nw_policy_peer() {
	spec=$1
	nw_policy_peers=$2
	for peer in "${nw_policy_peers[@]}"
	do
		if [ $peer = "ipBlock" ]; then
			echo "ipBlock";
		elif [ $peer = "namespaceSelector" ]; then
			echo "namespaceSelector";
		else
			echo "podSelector!!!";
		fi
	done
}

set_ingress() {
	ingress_list=($(echo "$1" | jq -r '.spec.ingress[] | keys | .[]'))

	for ingress in "${ingress_list[@]}"
	do
		if [ $ingress = "from" ]; then
			from=($(echo "$1" | jq -r .spec.ingress[] | jq -r '.from[] | keys | .[]'))
			set_ingress_nw_policy_peer $1 $from
		else
			# Todo: portsの処理
			:
		fi
	done
}

kubectl get networkpolicies.networking.k8s.io -A -o json | jq -c .items[] | while read -r item; do
    name=$(echo "$item" | jq -r .metadata.name)
	namespace=$(echo "$item" | jq -r .metadata.namespace)
	policy_types=($(echo "$item" | jq -r .spec.policyTypes[]))
	pod_labels=$(echo "$item" | jq -c '.spec.podSelector.matchLabels' | sed -e "s/{//" -e "s/}//" -e "s/\"//g" -e "s/:/=/")
	pod_ips=($(kubectl -n $namespace get pod -l $pod_labels -o json | jq -r .items[].status.podIP))

	set_ingress $item

	ipset_name=$(printf "%s-%s" $namespace $name)
	# ipsetが存在していなければ作成する
	stdout=$(sudo ipset list | grep $ipset_name)
	if [ -z "$stdout" ]; then
		printf "ipset create %s hash:ip\n" $ipset_name
		for pod_ip in "${pod_ips[@]}"
		do
			printf "ipset add %s %s\n" $ipset_name $pod_ip
		done
	else
		# 更新処理をすべきだがあとで考える
		:
	fi

	for policy in "${policy_types[@]}"
	do
		if [ $policy = "Ingress" ]; then
			:
		else
			:
		fi
	done
done
