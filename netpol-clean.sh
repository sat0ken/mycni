#!/bin/bash

netpol_items=($(kubectl get networkpolicies.networking.k8s.io -A -o json | jq -c -r '.items[]'))

length=${#netpol_items[@]}

# filterのルール数を取得
rules=$(iptables -t filter -L mycni_firewall | grep -v Chain | grep -v target | wc -l)

# # NWポリシーが設定されていない状態でipsetとiptablesのルールが残っている場合は消去する
if [[ "$length" -eq 0 ]]; then
  # 不要なルールを削除(他のルールも消しそうで危険)
  if [[ "$rules" -eq 0 ]]; then
    iptables -t filter -F mycni_firewall
  fi
  sleep 1
  # IPセットのリストを取得
  ipset_list=$(ipset list -n)
  # IPセットが存在するかどうかを確認
  if [[ -n "$ipset_list" ]]; then
    # 各IPセットをループして削除
    for set_name in $ipset_list; do
      ipset flush "$set_name"
      ipset destroy "$set_name"
    done
  fi
fi
