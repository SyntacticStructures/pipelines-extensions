#  local release_bundle_res_name=$(get_resource_name --type ReleaseBundle --operation IN)
#  local release_bundle_version=res_"$release_bundle_res_name"_version
#  local release_bundle_name=res_"$release_bundle_res_name"_name
#  local distribution_url=res_"$release_bundle_res_name"_sourceDistribution_url
#  local distribution_user=res_"$release_bundle_res_name"_sourceDistribution_user
#  local distribution_apikey=res_"$release_bundle_res_name"_sourceDistribution_apikey
#  local distribution_user=res_"$release_bundle_res_name"_sourceDistribution_user
#
#  # We call this endpoint to make sure the release bundle is ready.
#  # If it's ready it will return a download url.
#  local release_bundle_status_url="${!distribution_url}/api/v1/export/release_bundle/${!release_bundle_name}/${!release_bundle_version}/status"
#  local bundle_download_url=$(curl -XGET "$release_bundle_status_url" -u "${!distribution_user}:${!distribution_apikey}" | jq ."download_url")
#
#
#  local buildinfo_res_name=$(get_resource_name --type BuildInfo --operation IN)
#  local buildinfo_number=res_"$buildinfo_res_name"_buildNumber
#  local buildinfo_name=res_"$buildinfo_res_name"_buildName
#  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
#  local filespec_res_name=$(get_resource_name --type FileSpec --operation IN)
#  local res_targets=res_"$vm_cluster_name"_targets
#  local filespec_res_path=res_"$filespec_res_name"_resourcePath
#  local ssh_id="$HOME/.ssh/$vm_cluster_name"
#  local vm_addrs=( $(echo "${!res_targets}" | jq --raw-output '.[]') )
#
#  # We put everything we want to upload to vms in a directory
#  # We will create a tarball from all of it
#  local tardir="${PWD}/work"
#  mkdir "$tardir"
#  pushd "$tardir"
#    # download buildInfo artifacts to tardir
#    execute_command "jfrog rt dl "*" $tardir/ --build=${!buildinfo_name}/${!buildinfo_number}"
#    # move the fileSpec to tardir
#    mv "${!filespec_res_path}"/* "$tardir"/
#
#    # download and unzip release bundle
#    curl --remote-name -XGET "$bundle_download_url" -u "${!distribution_user}:${!distribution_apikey}"
#    unzip "${!release_bundle_name}"-"${!release_bundle_version}".zip
#
#    # creat tarball from everything in the tardir
#    local tarball_name="$pipeline_name-$run_id.tar.gz"
#    execute_command "tar -czvf ../$tarball_name ."
#  popd
export resp_body_file="$step_tmp_dir/response.json"
export release_bundle_version
export release_bundle_name
export distribution_url
export distribution_user
export distribution_apikey
export distribution_request_args
export distribution_curl_options


DeployApplication() {
  local buildinfo_res_name=$(get_resource_name --type BuildInfo --operation IN)

  local filespec_res_name=$(get_resource_name --type FileSpec --operation IN)
  local filespec_res_path=$(eval echo "$"res_"$filespec_res_name"_resourcePath)

  local releasebundle_res_name=$(get_resource_name --type ReleaseBundle --operation IN)

  local vm_cluster_name=$(get_resource_name --type VmCluster --operation IN)
  local res_targets=$(eval echo "$"res_"$vm_cluster_name"_targets)
  local ssh_id="$HOME/.ssh/$vm_cluster_name"
  local vm_addrs=( $(echo "$res_targets" | jq --raw-output '.[]') )

  res_types=( $buildinfo_res_name $filespec_res_name $releasebundle_res_name )
  if [ "${#res_types[@]}" != 1 ]; then
    execute_command "echo Exactly one resource of type BuildInfo\|ReleaseBundle\|FileSpec is supported."
    execute_command "exit 1"
  fi

  # We put everything we want to upload to vms in a directory
  # We will create a tarball from all of it
  # TODO: put this in a tmp dir
  local tardir="${PWD}/work"
  mkdir "$tardir"

  pushd "$tardir"
    if [ -n "$buildinfo_res_name" ]; then
      # download buildInfo artifacts to tardir
      local buildinfo_number=$(eval echo "$"res_"$buildinfo_res_name"_buildNumber)
      local buildinfo_name=$(eval echo "$"res_"$buildinfo_res_name"_buildName)
      local integration_alias
      integration_alias=$(find_resource_variable "$buildinfo_res_name" integrationAlias)
      local rt_url=$(eval echo "$"res_"$buildinfo_res_name"_"$integration_alias"_url)
      local rt_user=$(eval echo "$"res_"$buildinfo_res_name"_"$integration_alias"_user)
      local rt_apikey=$(eval echo "$"res_"$buildinfo_res_name"_"$integration_alias"_apikey)
      execute_command "retry_command jfrog rt config --insecure-tls=$no_verify_ssl --url $rt_url --user $rt_user --apikey $rt_apikey --interactive=false"
      execute_command "jfrog rt dl \"*\" $tardir/ --build=$buildinfo_name/$buildinfo_number"
    elif [ -n "$filespec_res_name" ]; then
      # move the fileSpecs to tardir
      execute_command "mv $filespec_res_path/* $tardir/"
    elif [ "$releasebundle_res_name" ]; then
      # Export and download release bundle
      local release_bundle_res_name=$(get_resource_name --type ReleaseBundle --operation IN)
      release_bundle_version=$(eval echo "$"res_"$release_bundle_res_name"_version)
      release_bundle_name=$(eval echo "$"res_"$release_bundle_res_name"_name)
      distribution_url=$(eval echo "$"res_"$release_bundle_res_name"_sourceDistribution_url)
      distribution_user=$(eval echo "$"res_"$release_bundle_res_name"_sourceDistribution_user)
      distribution_apikey=$(eval echo "$"res_"$release_bundle_res_name"_sourceDistribution_apikey)
      distribution_curl_options="-XGET --silent --retry 3 --write-out %{http_code}\n --output $resp_body_file -u $distribution_user:$distribution_apikey"
      if [ "$no_verify_ssl" == "true" ]; then
        distribution_curl_options+=" --insecure"
      fi

      # Check if release bundle was already exported
      local status_http_code=$(getDistributionExportStatus)

      # exit on bad response codes
      if [ "$status_http_code" -ne 200 ]; then
        execute_command "echo 'Could not get Release Bundle export status'"
        execute_command "echo http status: $status_http_code"
        execute_command "exit 1"
      fi

      # possible values: IN_PROGRESS|FAILED|NOT_TRIGGERED|NOT_EXPORTED|COMPLETED
      local export_status=$(cat "$resp_body_file" | jq -r .status)

      # export the Release Bundle if hasn't been exported yet
      handleExportStatus "$export_status"

      # wait for Release Bundle to be exported and check its status
      # we include COMPLETED job status here because we need the bundle archive download URL
      if [ "$export_status" != "FAILED" ]; then
        status_http_code=$(getDistributionExportStatus)
        local sleeperCount=2
        while [ "$status_http_code" -lt 299 ] && isReleaseBundleExporting; do
          execute_command "sleep $sleeperCount"
          sleeperCount+="$sleeperCount"
          if [ $sleeperCount -gt 64 ]; then
            # Keep checking for 128 seconds if export status hasn't reached COMPLETED yet
            break
          fi
          status_http_code=$(getDistributionExportStatus)
        done

        # exit on bad response codes
        if [ "$status_http_code" -ne 200 ]; then
          execute_command "echo 'Could not get Release Bundle export status'"
          execute_command "echo http status: $status_http_code"
          execute_command "exit 1"
        fi

        local resp_body=$(cat "$resp_body_file")
        export_status=$(echo "$resp_body" | jq -r .status)

        # exit on bad export status
        if [ "$export_status" != "COMPLETED" ]; then
          execute_command "echo 'Failed to export release bundle with status: $export_status'"
        fi

        execute_command "echo 'Exported Release Bundle $release_bundle_name/$release_bundle_version successfully'"
        exit 1
        # download release bundle
        local download_url=$(echo "$resp_body" | jq -r .download_url)
        status_http_code=$(downloadReleaseBundle "$download_url")

        # exit on bad response codes
        if [ "$status_http_code" -ne 200 ]; then
          execute_command "echo 'Could not get Release Bundle export status'"
          execute_command "echo http status: $status_http_code"
          execute_command "exit 1"
        fi
        execute_command "echo 'Downloaded Release Bundle $release_bundle_name/$release_bundle_version successfully'"

        execute_command "unzip $resp_body"
      fi
    fi
    # create tarball from everything in the tardir
    local tarball_name="$pipeline_name-$run_id.tar.gz"
    execute_command "tar -czvf ../$tarball_name ."
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

getDistributionExportStatus() {
  local request="curl $distribution_curl_options $distribution_url/api/v1/export/release_bundle/$release_bundle_name/$release_bundle_version/status"
  $request
}

exportReleaseBundle() {
  local request="curl $distribution_curl_options $distribution_url/api/v1/export/release_bundle/$release_bundle_name/$release_bundle_version"
  $request
}

downloadReleaseBundle() {
  download_url=$1
  local curl_options=$distribution_curl_options
  curl_options+=
  local request="curl $distribution_curl_options $download_url"
}

handleExportStatus() {
  export_status=$1

  # Trigger release bundle export if possible
  if [ "$export_status" == "NOT_TRIGGERED" ] || [ "$export_status" == "FAILED" ]; then
    execute_command "echo 'Exporting Release Bundle: $release_bundle_name/$release_bundle_version'"
    local export_http_code
    export_http_code=$(exportReleaseBundle)
    if [ "$export_http_code" -ne 202 ]; then
      execute_command "Failed to export release bundle"
      execute_command "exit 1"
    fi
    execute_command "echo 'Started export of Release Bundle $release_bundle_name}/$release_bundle_version}'"
  fi
}

isReleaseBundleExporting() {
  local status
  status=$(cat $resp_body_file | jq -r .status)
  if [ "$status" == "IN_PROGRESS" ] ||
   [ "$status" == "NOT_EXPORTED" ]; then
    return
  fi
  false
}

execute_command DeployApplication
