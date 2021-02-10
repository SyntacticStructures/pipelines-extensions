deployApplication() {
  # TODO: install rsync on the image. not here
#  apt-get install -y rsync

  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
  local app_filespec_name=$(get_resource_name --type FileSpec --operation IN)
  local res_targets=res_"$vm_cluster_name"_targets
  local app_resource_path=res_"$app_filespec_name"_resourcePath
  local ssh_id="$HOME/.ssh/$vm_cluster_name"
  local ip_addr=$(jq "${!res_targets}"[0] --raw-output --null-input)


  for i in "${${!res_targets}[@]}"
  do
    :
    echo "ipaddr >> $i"
  done

#  rsync "${!app_resource_path}" -e "ssh -i $ssh_id" "$ip_addr":"$step_configuration_targetDirectory" \
#  --ignore-times \
#  --archive \
#  --verbose \
#  --hard-links \
#  --perms
#
#  ssh -i "$ssh_id" "$ip_addr" "cd $step_configuration_targetDirectory/$app_filespec_name; $step_configuration_deployCommand"
}

execute_command deployApplication
