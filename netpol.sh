#!/bin/bash

# ipsetを作成しPodのIPを登録する
set_ipset_rules() {
  local set_ip_list=($1)
  local ipset_name=$2
  local ipset_type=$3

  # 存在しなければipsetのlistを新規作成
  stdout=$(ipset list | grep $ipset_name)
  if [ -z "$stdout" ]; then
    printf "ipset create %s %s\n" $ipset_name $ipset_type >> /tmp/cmd.sh
    for pod_ip in "${set_ip_list[@]}"
    do
      printf "ipset add %s %s\n" $ipset_name $pod_ip >> /tmp/cmd.sh
    done
  else
    # 既にルールがあったら更新処理をすべきだが対応していない
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
      # ipBlockに対応していない
      :
    elif [ $peer = "namespaceSelector" ]; then
      # namespaceSelectorに対応していない
      :
    else
      allow_pod_label=$(echo "$spec" | jq -c '.spec.ingress[].from[].podSelector.matchLabels' | sed -e "s/{//" -e "s/}//" -e "s/\"//g" -e "s/:/=/")
      allow_pod_ips=($(kubectl -n $namespace get pod -l $allow_pod_label -o json | jq -r .items[].status.podIP))
      set_ipset_rules "${allow_pod_ips[*]}" $allow_ipset_name "hash:ip"
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
    fi
  done

  # 作成したipsetの名前を戻り値として返す
  echo $allow_ipset_name
}

FILE=/tmp/cmd.sh
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
  ipset_type="hash:ip"

  # NW Polocyを設定する対象のPodのipsetを作成する
  target_ipset_name=$(printf "%s-%s-target" $namespace $name)
  set_ipset_rules "${pod_ips[*]}" $target_ipset_name $ipset_type

  for policy in "${policy_types[@]}"
  do
    # Ingressのみ対応している
    if [ $policy = "Ingress" ]; then
      allow_ipset_name=$(set_ingress $item)
      stdout=$(iptables -t filter -nL | grep $allow_ipset_name)
      if [ -z "$stdout" ]; then
        printf "iptables -A mycni_firewall --ipv4 -m set --match-set %s src -m set --match-set %s dst -j ACCEPT\n" $allow_ipset_name $target_ipset_name >> /tmp/cmd.sh
        printf "iptables -A mycni_firewall --ipv4 -m set ! --match-set %s src -m set --match-set %s dst -j DROP\n" $allow_ipset_name $target_ipset_name >> /tmp/cmd.sh
        /bin/bash /tmp/cmd.sh
      fi
    else
      :
    fi
  done
done
