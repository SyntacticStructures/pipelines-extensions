#!/bin/bash
set -e -o pipefail

source "./helpers.sh"

DeployApplication() {
  execute_command "printenv"
  exit 1
  local buildinfo_res_name=$(get_resource_name --type BuildInfo --operation IN)

  local filespec_res_name=$(get_resource_name --type FileSpec --operation IN)
  local filespec_res_path=$(eval echo "$"res_"$filespec_res_name"_resourcePath)

  local releasebundle_res_name=$(get_resource_name --type ReleaseBundle --operation IN)

  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
  local res_targets=$(eval echo "$"res_"$vm_cluster_name"_targets)
  local ssh_id="$HOME/.ssh/$vm_cluster_name"
  local vm_addrs=( $(echo "$res_targets" | jq --raw-output '.[]') )

  if [ -n "$DEPLOY_TARGETS_OVERRIDE" ]; then
    execute_command "echo 'Overriding vm deploy targets with: $DEPLOY_TARGETS_OVERRIDE'"
    IFS=,
    execute_command "echo $DEPLOY_TARGETS_OVERRIDE"
    vm_addrs=($DEPLOY_TARGETS_OVERRIDE)
    unset IFS
  fi

  res_types=( $buildinfo_res_name $filespec_res_name $releasebundle_res_name )
  if [ "${#res_types[@]}" != 1 ]; then
    execute_command "echo Exactly one resource of type BuildInfo\|ReleaseBundle\|FileSpec is supported."
    execute_command "exit 1"
  fi

  # We put everything we want to upload to vms in a directory
  # We will create a tarball from all of it
  local tardir="$step_tmp_dir/deploy-artifacts"
  mkdir "$tardir"

  pushd "$tardir"
    if [ -n "$buildinfo_res_name" ]; then
      buildinfo_integration_alias=$(find_resource_variable "$buildinfo_res_name" integrationAlias)
      downloadBuildinfo "$buildinfo_res_name" "$buildinfo_integration_alias"
    elif [ -n "$filespec_res_name" ]; then
      # move the fileSpecs to tardir
      # no need to download because filespecs are automatically downloaded already.
      execute_command "mv $filespec_res_path/* $tardir/"
    elif [ -n "$releasebundle_res_name" ]; then
      downloadReleaseBundle "$releasebundle_res_name"
    fi
    # create tarball from everything in the tardir
    local tarball_name="$pipeline_name-$run_id.tar.gz"
    execute_command "tar -czvf $step_tmp_dir/$tarball_name ."
  popd

  for i in "${!vm_addrs[@]}"
  do

    local vm_addr="${vm_addrs[$i]}"

    # Wait between deploys if delay was specified
    if [ -n "$step_configuration_rolloutDelay" ] && [ "$i" != 0 ]; then
      execute_command "sleep ${step_configuration_rolloutDelay}s"
    fi

    # Command to upload app tarball to vm
    # TODO: ssh-add, not scp -i
    local upload_command="scp -i $ssh_id $step_tmp_dir/$tarball_name $vm_addr:$step_configuration_targetDirectory"

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
      if [ -n "$step_configuration_postDeployCommand" ]; then
        post_deploy_command+="$ignore_failure_suffix"
      fi
    fi

    execute_command "$upload_command"
    execute_command "$deploy_command"

    if [ -n "$step_configuration_postDeployCommand" ]; then
      execute_command "$post_deploy_command"
    fi

  done
}

execute_command DeployApplication
