DeployApplication() {
   local buildinfo_name=$(get_resource_name --type BuildInfo --operation IN)
   local app_resource_path=res_"$buildinfo_name"_resourcePath
   ls "${!app_resource_path}"

   local app_resource_path2="${!"res_"$buildinfo_name"_resourcePath"}"
   ls $app_resource_path2
#  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
#  local app_filespec_name=$(get_resource_name --type FileSpec --operation IN)
#  local res_targets=res_"$vm_cluster_name"_targets
#  local app_resource_path=res_"$app_filespec_name"_resourcePath
#  local ssh_id="$HOME/.ssh/$vm_cluster_name"
#
#  # Convert json array to bash array
#  local vm_addrs=( $(echo "${!res_targets}" | jq --raw-output '.[]') )
#
#  app_filespec_tarball_name="$app_filespec_name.tar.gz"
#  execute_command "tar -czvf $app_filespec_tarball_name ${!app_resource_path}"
#
#  for i in "${!vm_addrs[@]}"
#  do
#
#    local vm_addr="${vm_addrs[$i]}"
#
#    # Wait between deploys if delay was specified
#    if [ -n "$step_configuration_rolloutDelay" ] && [ "$i" != 1 ]; then
#      execute_command "sleep ${step_configuration_rolloutDelay}s"
#    fi
#
#    # Command to upload app tarball to vm
#    local upload_command="scp -i $ssh_id ./$app_filespec_tarball_name $vm_addr:$step_configuration_targetDirectory"
#
#    # Command to run the deploy command from within the uploaded dir
#    local untar="cd $step_configuration_targetDirectory/; tar -xvf $app_filespec_tarball_name; rm -f $app_filespec_tarball_name;"
#    local deploy="cd $app_filespec_name; $step_configuration_deployCommand;"
#    local deploy_command="ssh -i $ssh_id -n $vm_addr \"$untar $deploy\""
#
#    # Command to run after the deploy command from within the uploaded dir
#    local post_deploy_command="ssh -i $ssh_id \
#    -n $vm_addr \
#    \"cd $step_configuration_targetDirectory/$app_filespec_name; $step_configuration_postDeployCommand\""
#
#
#    # Don't exit on failed commands if fastFail is specified as false
#    if [ -n "$step_configuration_fastFail" ] && [ "$step_configuration_fastFail" == false ]; then
#      ignore_failure_suffix=" || continue"
#      upload_command+="$ignore_failure_suffix"
#      deploy_command+="$ignore_failure_suffix"
#      if [ -n "$post_deploy_command" ]; then
#        post_deploy_command+="$ignore_failure_suffix"
#      fi
#    fi
#
#    execute_command "$upload_command"
#    execute_command "$deploy_command"
#
#    if [ -n "$post_deploy_command" ]; then
#      execute_command "$post_deploy_command"
#    fi
#
#  done
}

execute_command DeployApplication
