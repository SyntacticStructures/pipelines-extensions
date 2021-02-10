deployApplication() {
#  printenv
  # TODO: install rsync on imageBuilds
   apt-get install -y rsync

   local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
   local app_filespec_name=$(get_resource_name --type FileSpec --operation IN)
   local res_targets=res_"$vm_cluster_name"_targets
   local app_resource_path_var_name=res_"$app_filespec_name"_
   local ip_addr=$(jq "${!res_targets}"[0] --raw-output --null-input)
   local ssh_id="$HOME/.ssh/$vm_cluster_name"


#  get_resource_name --type FileSpec --operation IN
  rsync -e "ssh -i $ssh_id" "$res_myApp_resourcePath" "$ip_addr":"$step_configuration_targetDirectory"
#  ssh -i "$ssh_id" "$ip_addr" "cd $step_configuration_targetDirectory; $step_configuration_deployCommand"

  echo "deployApplication running"
}

execute_command deployApplication
