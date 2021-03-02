DeployApplication() {
  local buildinfo_res_name=$(get_resource_name --type BuildInfo --operation IN)

  local filespec_res_name=$(get_resource_name --type FileSpec --operation IN)
  local filespec_res_path=res_"$filespec_res_name"_resourcePath

  local releasebundle_res_name=$(get_resource_name --type ReleaseBundle --operation IN)

  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
  local res_targets=res_"$vm_cluster_name"_targets
  local ssh_id="$HOME/.ssh/$vm_cluster_name"
  local vm_addrs=( $(echo "${!res_targets}" | jq --raw-output '.[]') )

  res_types=( $buildinfo_res_name $filespec_res_name $releasebundle_res_name )
  if [ "${#res_types[@]}" != 1 ]; then
    execute_command "echo Exactly one resource of type BuildInfo\|ReleaseBundle\|FileSpec is supported."
    exit 1
  fi

  # We put everything we want to upload to vms in a directory
  # We will create a tarball from all of it
  # TODO: put this in a tmp dir
  local tardir="${PWD}/work"
  mkdir "$tardir"

  if [ -n "$buildinfo_res_name" ]; then
    # download buildInfo artifacts to tardir
    local buildinfo_number=res_"$buildinfo_res_name"_buildNumber
    local buildinfo_name=res_"$buildinfo_res_name"_buildName
    local integration_alias=$(find_resource_variable "$buildinfo_res_name" integrationAlias)
    local rt_url=res_"$buildinfo_res_name"_"$integration_alias"_url
    local rt_user=res_"$buildinfo_res_name"_"$integration_alias"_user
    local rt_apikey=res_"$buildinfo_res_name"_"$integration_alias"_apikey
    retry_command jfrog rt config --insecure-tls="$no_verify_ssl" --url "${!rt_url}" --user "${!rt_user}" --apikey "${!rt_apikey}" --interactive=false
    execute_command "jfrog rt dl \"*\" $tardir/ --build=${!buildinfo_name}/${!buildinfo_number}"
  elif [ -n "$filespec_res_name" ]; then
    # move the fileSpecs to tardir
    execute_command "mv ${!filespec_res_path}/* $tardir/"
  elif [ "$releasebundle_res_name" ]; then
    # TODO: support releaseBundles
    echo "release bundles not yet supported"
    exit 1
  fi

  # create tarball from everything in the tardir
  local tarball_name="$pipeline_name-$run_id.tar.gz"
  execute_command "tar -czvf ../$tarball_name $tardir"

  for i in "${!vm_addrs[@]}"
  do

    local vm_addr="${vm_addrs[$i]}"

    # Wait between deploys if delay was specified
    if [ -n "$step_configuration_rolloutDelay" ] && [ "$i" != 1 ]; then
      execute_command "sleep ${step_configuration_rolloutDelay}s"
    fi

    # Command to upload app tarball to vm
    # TODO: ssh-add, not scp -i
    execute_command "ls"
    execute_command "pwd"
    local upload_command="scp -i $ssh_id ./$tarball_name $vm_addr:$step_configuration_targetDirectory"

    # Command to run the deploy command from within the uploaded dir
    local untar="cd $step_configuration_targetDirectory/; tar -xvf $tarball_name; rm -f $tarball_name;"
    local deploy_command="ssh -i $ssh_id -n $vm_addr \"$untar $step_configuration_deployCommand\""

    # Command to run after the deploy command from within the uploaded dir
    local post_deploy_command="ssh -i $ssh_id \
    -n $vm_addr \
    \"cd $step_configuration_targetDirectory; $step_configuration_postDeployCommand\""


    # Don't exit on failed commands if fastFail is specified as false
    if [ -n "$step_configuration_fastFail" ] && [ "$step_configuration_fastFail" == false ]; then
      ignore_failure_suffix=" || continue"
      upload_command+="$ignore_failure_suffix"
      deploy_command+="$ignore_failure_suffix"
      if [ -n "$post_deploy_command" ]; then
        post_deploy_command+="$ignore_failure_suffix"
      fi
    fi

    execute_command "$upload_command"
    execute_command "$deploy_command"

    if [ -n "$post_deploy_command" ]; then
      execute_command "$post_deploy_command"
    fi

  done
}

execute_command DeployApplication
