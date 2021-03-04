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
      local buildinfo_number=res_"$buildinfo_res_name"_buildNumber
      local buildinfo_name=res_"$buildinfo_res_name"_buildName
      local integration_alias=$(find_resource_variable "$buildinfo_res_name" integrationAlias)
      local rt_url=res_"$buildinfo_res_name"_"$integration_alias"_url
      local rt_user=res_"$buildinfo_res_name"_"$integration_alias"_user
      local rt_apikey=res_"$buildinfo_res_name"_"$integration_alias"_apikey
      execute_command "retry_command jfrog rt config --insecure-tls=$no_verify_ssl --url ${!rt_url} --user ${!rt_user} --apikey ${!rt_apikey} --interactive=false"
      execute_command "jfrog rt dl \"*\" $tardir/ --build=${!buildinfo_name}/${!buildinfo_number}"
    elif [ -n "$filespec_res_name" ]; then
      # move the fileSpecs to tardir
      execute_command "mv ${!filespec_res_path}/* $tardir/"
    elif [ "$releasebundle_res_name" ]; then
      # Export and download release bundle
      local release_bundle_res_name=$(get_resource_name --type ReleaseBundle --operation IN)
      local release_bundle_version=res_"$release_bundle_res_name"_version
      local release_bundle_name=res_"$release_bundle_res_name"_name
      local distribution_url=res_"$release_bundle_res_name"_sourceDistribution_url
      local distribution_user=res_"$release_bundle_res_name"_sourceDistribution_user
      local distribution_apikey=res_"$release_bundle_res_name"_sourceDistribution_apikey
      # TODO: Check for ready status before exporting. It may already by exported.

      execute_command "echo ${!distribution_url}"
      execute_command "echo ${!release_bundle_version}"
      execute_command "echo ${!release_bundle_name}"
      execute_command "echo ${!distribution_url}"
      execute_command "echo ${!distribution_user}"
      execute_command "echo ${!distribution_apikey}"

      local resp_body_file="$step_tmp_dir/response.json"
      local distribution_request_args=("${!distribution_url}" "${!release_bundle_name}" "${!release_bundle_version}" "${!distribution_user}" "${!distribution_apikey}" "$resp_body_file")
      # Check if release bundle was already exported
      local status_http_code=$(getDistributionExportStatus "${distribution_request_args[@]}")
      execute_command "cat $resp_body_file"
      execute_command "echo $status_http_code"
      exit 1

      # check status
      if [ $status_http_code -eq 404 ]; then
        execute_command "echo 'Release Bundle ${!release_bundle_name}/${!release_bundle_version} not found. Please check your Release Bundle details'"
        execute_command "exit 1"
      elif [ $status_http_code -eq 200 ]; then
        execute_command "echo 'got here'"
        execute_command "local export_status=\$(cat "$resp_body_file" | jq -r .status)"
        if [ "$export_status" == "NOT_TRIGGERED" ]; then
          execute_command "echo 'Release Bundle ${!release_bundle_name}/${!release_bundle_version} export was not triggered yet. We will trigger it now'"
        elif [ "$export_status" == "COMPLETED" ]; then
          execute_command "echo 'Release Bundle ${!release_bundle_name}/${!release_bundle_version} export was already created. We will download it now'"
          deleteExportedBundleOnFinish="false"
          export_status="COMPLETED"
        elif [ "$export_status" == "IN_PROGRESS" ] || [ "$export_status" == "NOT_EXPORTED" ] ; then
          execute_command "echo 'Release Bundle ${!release_bundle_name}/${!release_bundle_version} export is in progress. Will wait for it to be completed'"
          deleteExportedBundleOnFinish="false"
          export_status="IN_PROGRESS"
        elif [ "$export_status" == "FAILED" ]; then
          execute_command "echo 'Release Bundle ${!release_bundle_name}/${!release_bundle_version} export failed before. Trying to trigger an export again.'"
          export_status="FAILED"
        fi
      else
        execute_command "echo 'Release Bundle ${!release_bundle_name}/${!release_bundle_version} status=$export_status is unexpected. Aborting... '"
        execute_command "exit 1"
      fi
      # export the Release Bundle if hasn't been exported yet
      if [ "$export_status" == "NOT_TRIGGERED" ] ||[ "$export_status" == "FAILED" ]; then

        execute_command "echo 'Triggering Release Bundle download for ${!release_bundle_name}/${!release_bundle_version}'"
        local export_http_code=$(exportReleaseBundle "${distribution_request_args[@]}")
        if [ "$export_http_code" -gt 299 ]; then
          execute_command "echo 'Triggering Release Bundle download failed ${!release_bundle_name}/${!release_bundle_version} failed with status code $export_http_code'"
          if [ "$export_http_code" -eq 404 ]; then
            execute_command "echo 'Release Bundle ${!release_bundle_name}/${!release_bundle_version} not found'"
          fi
          execute_command "exit 1"
        elif [ "$export_http_code" -eq 202 ]; then
          execute_command "echo 'Successfully scheduled export of Release Bundle ${!release_bundle_name}/${!release_bundle_version}'"
        else
          execute_command "echo 'Exporting Release Bundle ${!release_bundle_name}/${!release_bundle_version} finished with unexpected status code $export_http_code'"
          execute_command "exit 1"
        fi
        export_status="TRIGGERED"
      fi
    fi
    echo "$export_status"
    execute_command "echo killing the program"
    execute_command "exit 1"
    # create tarball from everything in the tardir
    execute_command "echo got past it"
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
  local distribution_url=$1
  local release_bundle_name=$2
  local release_bundle_version=$3
  local distribution_user=$4
  local distribution_apikey=$5
  local resp_body_file=$6

  local curl_options="-XGET --silent --retry 3 --write-out '%{http_code}\n' --output $resp_body_file -u $distribution_user:$distribution_apikey"

  if [ "$no_verify_ssl" == "true" ]; then
    curl_options+=" --insecure"
  fi

  execute_command "echo: release_bundle_version $release_bundle_version"
  execute_command "echo: release_bundle_name    $release_bundle_name"
  execute_command "echo: distribution_url       $distribution_url"
  execute_command "echo: distribution_user      $distribution_user"
  execute_command "echo: distribution_apikey    $distribution_apikey"

  local request="curl $curl_options $distribution_url/api/v1/export/release_bundle/${!release_bundle_name}/${!release_bundle_version}/status"
  execute_command "echo $request"
  $request
}

exportReleaseBundle() {
  local distribution_url=$1
  local release_bundle_name=$2
  local release_bundle_version=$3
  local distribution_user=$4
  local distribution_apikey=$5
  local resp_body_file=$6
  local curl_options="-XGET --silent --retry 3 --write-out '%{http_code}\n' --output $resp_body_file -u $distribution_user:$distribution_apikey"

      execute_command "echo: distribution_url       $distribution_url"
      execute_command "echo: release_bundle_version $release_bundle_version"
      execute_command "echo: release_bundle_name    $release_bundle_name"
      execute_command "echo: distribution_url       $distribution_url"
      execute_command "echo: distribution_user      $distribution_user"
      execute_command "echo: distribution_apikey    $distribution_apikey"

  if [ "$no_verify_ssl" == "true" ]; then
    curlOptions+=" --insecure"
  fi
  $export_status
  local request="curl $curlOptions $distributionUrl/api/v1/export/release_bundle/$releaseBundleName/$releaseBundleVersion"
  $request
}

execute_command DeployApplication
