DeployApplication() {
  # TODO: install rsync on the image. not here
  apt-get install -y rsync > /dev/null 2>&1

  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
  local app_filespec_name=$(get_resource_name --type FileSpec --operation IN)
  local res_targets=res_"$vm_cluster_name"_targets
  local app_resource_path=res_"$app_filespec_name"_resourcePath
  local ssh_id="$HOME/.ssh/$vm_cluster_name"

  # Convert json array to bash array
  local vm_addrs=( $(echo "${!res_targets}" | jq --raw-output '.[]') )

  # Override VMCluster resource ip addrs
  # if DEPLOY_TARGETS are specified
  if [ -n "$DEPLOY_TARGETS" ]; then
    # Convert csv to bash array
    vm_addrs=( $(echo "$DEPLOY_TARGETS" | tr ',' '\n') )
  fi

  # Append extra vm addrs
  # if ADDITIONAL_TARGETS is specified
  if [ -n "$ADDITIONAL_TARGETS" ]; then
    vm_addrs=( "${vm_addrs[@]}" $(echo "$ADDITIONAL_TARGETS" | tr ',' '\n') )
  fi

  app_filespec_tarball_name="$app_filespec_name.tar.gz"
  execute_command "tar -czvf $app_filespec_tarball_name ${!app_resource_path}"

  for i in "${!vm_addrs[@]}"
  do

    local vm_addr="${vm_addrs[$i]}"

    # Wait between deploys if delay was specified
    if [ -n "$step_configuration_rolloutDelay" ] && [ "$i" != 1 ]; then
      execute_command "sleep ${step_configuration_rolloutDelay}s"
    fi

    # Command to upload app dir to vm, preserving any hardlinks or permissions
    local upload_command="rsync ${!app_resource_path} -e \"ssh -i $ssh_id\" $vm_addr:$step_configuration_targetDirectory \
    --ignore-times \
    --archive \
    --hard-links \
    --perms"

    # Command to run the deploy command from within the uploaded dir
#    local deploy_command="ssh -i $ssh_id \
#    -n $vm_addr \
#    \"cd $step_configuration_targetDirectory/$app_filespec_name; $step_configuration_deployCommand\""
    local deploy_command="ssh -i $ssh_id \
    -n $vm_addr \
    \"cd $step_configuration_targetDirectory/$app_filespec_name; ls -a \""

    # Command to run after the deploy command from within the uploaded dir
#    local post_deploy_command="ssh -i $ssh_id \
#    -n $vm_addr \
#    \"cd $step_configuration_targetDirectory/$app_filespec_name; $step_configuration_postDeployCommand\""


    # Don't exit on failed commands if fastFail is specified as false
    if [ -n "$step_configuration_fastFail" ] && [ "$step_configuration_fastFail" == false ]; then
      fast_fail_suffix=" || continue"
      upload_command+="$fast_fail_suffix"
      deploy_command+="$fast_fail_suffix"
      post_deploy_command+="$fast_fail_suffix"
    fi

    execute_command "$upload_command"
    execute_command "$deploy_command"
    execute_command "$post_deploy_command"
  done
}

execute_command DeployApplication
