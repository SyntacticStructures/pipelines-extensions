#!/bin/bash
set -e -o pipefail

source "./helpers.sh"

DeployApplication() {
  local buildinfo_res_name=$(get_resource_name --type BuildInfo --operation IN)

  local filespec_res_name=$(get_resource_name --type FileSpec --operation IN)
  local filespec_res_path=$(eval echo "$"res_"$filespec_res_name"_resourcePath)

  local releasebundle_res_name=$(get_resource_name --type ReleaseBundle --operation IN)

  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
  local res_targets=$(eval echo "$"res_"$vm_cluster_name"_targets)
  local ssh_id="$HOME/.ssh/$vm_cluster_name"
  local vm_targets=( $(echo "$res_targets" | jq --raw-output '.[]') )

  execute_command "ssh -i /root/.ssh/myVM -n root@192.168.50.3 -o StrictHostKeyChecking=no \"ls /\""


  res_types=( $buildinfo_res_name $filespec_res_name $releasebundle_res_name )
  if [ "${#res_types[@]}" != 1 ]; then
    execute_command "echo Exactly one resource of type BuildInfo\|ReleaseBundle\|FileSpec is supported."
    execute_command "exit 1"
  fi

  if [ -n "$DEPLOY_TARGETS_OVERRIDE" ]; then
    execute_command "echo 'Overriding vm deploy targets with: $DEPLOY_TARGETS_OVERRIDE'"
    IFS=,
    vm_targets=($DEPLOY_TARGETS_OVERRIDE)
    unset IFS
  fi

  # We put everything we want to upload to vms in a directory
  # We will create a tarball from all of it
  local tardir="$step_tmp_dir/deploy-artifacts"
  mkdir "$tardir"

  # Create a file with env vars to source on the target vms
  local vm_env_filename="$step_name-$run_id.env"
  local vm_env_file_path="$tardir/$vm_env_filename"
  if [ -n "$step_configuration_vmEnvironmentVariables_len" ];then
    for ((i=0; i<step_configuration_vmEnvironmentVariables_len; i++)); do
      env_var=$(eval echo "$"step_configuration_vmEnvironmentVariables_"$i")
      execute_command "echo export $(echo "$env_var") >> $vm_env_file_path"
    done
    execute_command "cat $vm_env_file_path"
  fi

  pushd "$tardir"
    if [ -n "$buildinfo_res_name" ]; then
      buildinfo_integration_alias=$(find_resource_variable "$buildinfo_res_name" integrationAlias)
      downloadBuildInfo "$buildinfo_res_name" "$buildinfo_integration_alias"
    elif [ -n "$filespec_res_name" ]; then
      # move the fileSpecs to tardir
      # no need to download because filespecs are automatically downloaded already.
      execute_command "mv $filespec_res_path/* $tardir/"
    elif [ -n "$releasebundle_res_name" ]; then
      downloadReleaseBundle "$releasebundle_res_name"
    fi
    # create tarball from everything in the tardir
    local tarball_name="$step_name-$run_id.tar.gz"
    execute_command "tar -czvf $step_tmp_dir/$tarball_name ."
  popd

  local failed_vms=()

  for i in "${!vm_targets[@]}"
  do

    local vm_target="${vm_targets[$i]}"

    # Wait between deploys if delay was specified
    if [ -n "$step_configuration_rolloutDelay" ] && [ "$i" != 0 ]; then
      execute_command "sleep ${step_configuration_rolloutDelay}s"
    fi

    # TODO: ssh-add, not scp -i
    local ssh_base_command="ssh -i $ssh_id -n $step_configuration_sshUser@$vm_target -o StrictHostKeyChecking=no"

    local target_dir="~/$step_name/$run_id"
    if [ -n "$step_configuration_targetDirectory" ]; then
      target_dir=$step_configuration_targetDirectory
    fi
    local make_target_dir_command="$ssh_base_command \"mkdir -p $target_dir\""

    # Command to upload app tarball to vm
    local upload_command="scp -i $ssh_id $step_tmp_dir/$tarball_name $vm_target:$target_dir"

    # Command to run the deploy command from within the uploaded dir
    local untar="cd $target_dir/; tar -xvf $tarball_name; rm -f $tarball_name;"

    # Command to source the file with vmEnvironmentVariables
    local source_env_file
    if [ -n "$step_configuration_vmEnvironmentVariables_len" ]; then
      source_env_file="source $target_dir/$vm_env_filename;"
    fi
    local deploy_command="$ssh_base_command \"$untar $source_env_file $step_configuration_deployCommand\""

    # Command to run after the deploy command from within the uploaded dir
    local post_deploy_command="$ssh_base_command \
    \"cd $target_dir; $source_env_file $step_configuration_postDeployCommand\""

    on_failure='break'
    # Don't exit on failed commands if fastFail is specified as false
    if [ -n "$step_configuration_fastFail" ] && [ "$step_configuration_fastFail" == false ]; then
      on_failure='continue'
    fi

    execute_command "echo Creating target dir on vm"
    execute_command "$make_target_dir_command || failed_vms+=($vm_target); eval $on_failure"
    execute_command "echo Uploading artifacts to vm"
    execute_command "$upload_command || failed_vms+=($vm_target); eval $on_failure"
    execute_command "echo Running deploy command"
    execute_command "$deploy_command || failed_vms+=($vm_target); eval $on_failure"

    if [ -n "$step_configuration_postDeployCommand" ]; then
      execute_command "echo Running post-deploy command"
      execute_command "$post_deploy_command || failed_vms+=($vm_target); eval $on_failure"
    fi

    # Deploy was successful.

    local rollback_dir="~/$step_name/rollback"
    # Command to copy artifacts into rollback dir.
    create_rollback_artifacts="$ssh_base_command \"mkdir -p $rollback_dir; rm -rf $rollback_dir/*; cp -r $target_dir/* $rollback_dir\""
    execute_command "echo 'Archiving successful deploy for rollback'"
    execute_command "$create_rollback_artifacts"

  done

  # Do rollback
  if [ -n "$step_configuration_rollbackCommand" ] && [ "${#failed_vms[@]}" -gt 0 ]; then
    for vm_target in "${vm_targets[@]}"; do
      execute_command "echo 'Executing rollback command on vm: $vm_target'"
      local ssh_base_command="ssh -i $ssh_id -n $step_configuration_sshUser@$vm_target"
      # If rollback fails, keep trying to roll back other vms
      execute_command "$ssh_base_command \"$step_configuration_rollbackCommand\" || continue"
    done
  fi
}

DeployApplication
