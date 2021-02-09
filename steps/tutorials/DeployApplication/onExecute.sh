deployApplication() {
#  printenv
  # TODO: install rsync on imageBuilds
#   apt-get install -y rsync
   local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
   local res_targets_var_name=res_"$vm_cluster_name"_targets
   echo $"${res_targets_var_name}"
#   local ip_addr=$(jq $"$res_targets_var_name"[0] --raw-output --null-input)
#   echo "$ip_addr"
#  local ssh_id="$HOME/.ssh/myVM"


#  get_resource_name --type FileSpec --operation IN
#  rsync -e "ssh -i $ssh_id" "$res_myApp_resourcePath" "$ip_addr":"$step_configuration_targetDirectory"
#  ssh -i "$ssh_id" "$ip_addr" "cd $step_configuration_targetDirectory; $step_configuration_deployCommand"

  echo "deployApplication running"
}

execute_command deployApplication
