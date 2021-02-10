deployApplication() {
#  apt-get install -y rsync

  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
  local app_filespec_name=$(get_resource_name --type FileSpec --operation IN)
  local res_targets=res_"$vm_cluster_name"_targets
  local app_resource_path=res_"$app_filespec_name"_resourcePath
  local ip_addr=$(jq "${!res_targets}"[0] --raw-output --null-input)
  local ssh_id="$HOME/.ssh/$vm_cluster_name"

  ls ${!app_resource_path}

  rsync -e "ssh -i $ssh_id" "${!app_resource_path}" "$ip_addr":"$step_configuration_targetDirectory" --ignore-times
  ssh -i "$ssh_id" "$ip_addr" "cd $step_configuration_targetDirectory; $step_configuration_deployCommand"

  echo "deployApplication running"
}

execute_command deployApplication
