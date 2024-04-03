#!/bin/bash

kubectl get networkpolicies.networking.k8s.io -A -o json | jq -c .items[] | while read -r item; do
    name=$(echo "$item" | jq -r .metadata.name)
	namespace=$(echo "$item" | jq -r .metadata.namespace)
	policy_types=($(echo "$item" | jq -r .spec.policyTypes[]))
	pod_labels=$(echo "$item" | jq -c '.spec.podSelector.matchLabels' | sed -e "s/{//" -e "s/}//" -e "s/\"//g" -e "s/:/=/")
	pod_ips=($(kubectl -n $namespace get pod -l $pod_labels -o json | jq -r .items[].status.podIP))

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
