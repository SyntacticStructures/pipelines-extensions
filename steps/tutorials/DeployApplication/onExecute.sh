get_resource_names() {
  if [[ $# -le 0 ]]; then
    echo "Usage: get_resource_name [--type] [--operation] [--syntax-version] [--namespace]" >&2
    exit 99
  fi

  local resource_name=""
  local resource_type=""
  local resource_operation=""
  local resource_version=""
  local resource_namespace="jfrog"

  if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
      ARGUMENT="$1"
      case $ARGUMENT in
        --type)
          resource_type="$2"
          shift
          shift
          ;;
        --operation)
          resource_operation="$2"
          shift
          shift
          ;;
        --syntax-version)
          resource_version="$2"
          shift
          shift
          ;;
        --namespace)
          resource_namespace="$2"
          shift
          shift
          ;;
        *)
          echo "Warning: Unrecognized flag \"$1\"" >&2
          shift
          ;;
      esac
    done
  fi

  if [ -z "$resource_type" ]; then
    echo "Resource type is not specified. Please use --type to specify resource type" >&2
    exit 99
  fi

  if [ -z "$resource_operation" ]; then
    echo "Resource operation is not specified. Please use --operation to specify resource operation" >&2
    exit 99
  fi

  for resource in $(cat "$step_json_path" | jq -r '.resources | keys[]'); do
    local resource_json=$(cat "$step_json_path" | jq -r '.resources.'$resource'')
    if [ "$resource_json" != "null" ] || [ ! -z "$resource_json" ]; then
      local resource_json_type=$(echo "$resource_json" | jq -r .resourceType)
      local resource_json_version=$(echo "$resource_json" | jq -r .syntaxVersion)
      local resource_json_operation_type=$(echo "$resource_json" | jq -r '.operations | type')
      local resource_json_namespace=$(echo "$resource_json" | jq -r '.namespace')
      local resource_json_operation=""
      if [ "$resource_json_operation_type" == "array" ]; then
        resource_json_operation=$(echo "$resource_json" | jq -r .operations[0])
      fi
      if [ "$resource_type" == "$resource_json_type" ] && [ "$resource_operation" == "$resource_json_operation" ] && [ "$resource_namespace" == "$resource_json_namespace" ]; then
        if [ ! -z "$resource_version" ]; then
          if [ "$resource_version" == "$resource_json_version" ]; then
            resource_name+=$resource
            break
          fi
        else
          resource_name+=$resource
          break
        fi
      fi
    fi
  done

  echo "$resource_name"
}

DeployApplication() {
#  local release_bundle_res_name=$(get_resource_name --type ReleaseBundle --operation IN)
#  local release_bundle_version=res_"$release_bundle_res_name"_version
#  local release_bundle_name=res_"$release_bundle_res_name"_name
#  local distribution_url=res_"$release_bundle_res_name"_sourceDistribution_url
#  local distribution_user=res_"$release_bundle_res_name"_sourceDistribution_user
#  local distribution_apikey=res_"$release_bundle_res_name"_sourceDistribution_apikey
#  local distribution_user=res_"$release_bundle_res_name"_sourceDistribution_user

  # We call this endpoint to make sure the release bundle is ready.
  # If it's ready it will return a download url.
#  local release_bundle_status_url="${!distribution_url}/api/v1/export/release_bundle/${!release_bundle_name}/${!release_bundle_version}/status"
#  local bundle_download_url=$(curl -XGET "$release_bundle_status_url" -u "${!distribution_user}:${!distribution_apikey}" | jq ."download_url" --insecure)


#  local buildinfo_res_name=$(get_resource_name --type BuildInfo --operation IN)
#  local buildinfo_number=res_"$buildinfo_res_name"_buildNumber
#  local buildinfo_name=res_"$buildinfo_res_name"_buildName
#  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
  local filespec_res_name=$(get_resource_names --type FileSpec --operation IN)
  echo "$filespec_res_name"
#  local res_targets=res_"$vm_cluster_name"_targets
#  local filespec_res_path=res_"$filespec_res_name"_resourcePath
#  local ssh_id="$HOME/.ssh/$vm_cluster_name"
#  local vm_addrs=( $(echo "${!res_targets}" | jq --raw-output '.[]') )

  # We put everything we want to upload to vms in a directory
  # We will create a tarball from all of it
#  local tardir="${PWD}/work"
#  mkdir "$tardir"
#  pushd "$tardir"
#    # download buildInfo artifacts to tardir
#    execute_command "jfrog rt dl "*" $tardir/ --build=${!buildinfo_name}/${!buildinfo_number}"
#    # move the fileSpec to tardir
#    mv "${!filespec_res_path}"/* "$tardir"/
#
#    # download and unzip release bundle
##    execute_command "curl -o --insecure -XGET ${!bundle_download_url} -u ${!distribution_user}:${!distribution_apikey}"
##    unzip "${!release_bundle_name}"-"${!release_bundle_version}".zip
#
#    # creat tarball from everything in the tardir
#    local tarball_name="$pipeline_name-$run_id.tar.gz"
#    execute_command "tar -czvf ../$tarball_name ."
#  popd
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
#    local upload_command="scp -i $ssh_id ./$tarball_name $vm_addr:$step_configuration_targetDirectory"
#
#    # Command to run the deploy command from within the uploaded dir
#    local untar="cd $step_configuration_targetDirectory/; tar -xvf $tarball_name; rm -f $tarball_name;"
#    local deploy_command="ssh -i $ssh_id -n $vm_addr \"$untar $step_configuration_deployCommand\""
#
#    # Command to run after the deploy command from within the uploaded dir
#    local post_deploy_command="ssh -i $ssh_id \
#    -n $vm_addr \
#    \"cd $step_configuration_targetDirectory; $step_configuration_postDeployCommand\""
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
