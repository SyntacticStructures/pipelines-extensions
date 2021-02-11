DeployApplication() {
  # TODO: install rsync on the image. not here
  apt-get install -y rsync > /dev/null 2>&1

  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
  local app_filespec_name=$(get_resource_name --type FileSpec --operation IN)
  local res_targets=res_"$vm_cluster_name"_targets
  local app_resource_path=res_"$app_filespec_name"_resourcePath
  local ssh_id="$HOME/.ssh/$vm_cluster_name"

  # Iterate over json array of vm addresses.
  # We can't use a regular for loop because it's a json string, not a bash array.
  echo "${!res_targets}" | jq -c '.[]' --raw-output | while ((idx++)); read -r vm_addr; do

    # Wait between deploys if delay was specified
    if [ -n "$step_configuration_rolloutDelay" ] && [ "$idx" != 1 ]; then
      execute_command "sleep ${step_configuration_rolloutDelay}s"
    fi

    # Upload app dir to vm, preserving any hardlinks or permissions
    execute_command "rsync ${!app_resource_path} -e \"ssh -i $ssh_id\" $vm_addr:$step_configuration_targetDirectory \
    --ignore-times \
    --archive \
    --hard-links \
    --perms"

    # Run the deploy command from within the uploaded dir
    execute_command "ssh -i $ssh_id \
    -n $vm_addr \
    \"cd $step_configuration_targetDirectory/$app_filespec_name; $step_configuration_deployCommand\""

  done
}

DeployApplication
