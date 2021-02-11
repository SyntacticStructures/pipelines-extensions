deployApplication() {
  # TODO: install rsync on the image. not here
  apt-get install -y rsync

  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
  local app_filespec_name=$(get_resource_name --type FileSpec --operation IN)
  local res_targets=res_"$vm_cluster_name"_targets
  local app_resource_path=res_"$app_filespec_name"_resourcePath
  local ssh_id="$HOME/.ssh/$vm_cluster_name"

  echo "${!res_targets}" | jq -c '.[]' --raw-output | while read -r vm_addr; do
    echo "Deploying $app_filespec_name to $vm_addr..."
    rsync "${!app_resource_path}" -e "ssh -i $ssh_id" "$vm_addr":"$step_configuration_targetDirectory" \
    --ignore-times \
    --archive \
    --hard-links \
    --perms


    echo "Running $step_configuration_deployCommand on $vm_addr..."
    ssh -i "$ssh_id" \
    -n "$vm_addr" \
    "cd $step_configuration_targetDirectory/$app_filespec_name; $step_configuration_deployCommand"

  done

}

execute_command deployApplication
