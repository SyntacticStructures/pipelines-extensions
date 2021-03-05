export resp_body_file="$step_tmp_dir/response.json"
export release_bundle_version
export release_bundle_name
export distribution_url
export distribution_user
export distribution_apikey
export distribution_request_args
export distribution_curl_options

__getDistributionExportStatus() {
  local curl_options=$distribution_curl_options
  curl_options+=" -XGET"
  local request="curl $curl_options $distribution_url/api/v1/export/release_bundle/$release_bundle_name/$release_bundle_version/status"
  $request
}

__exportReleaseBundle() {
  local curl_options=$distribution_curl_options
  curl_options+=" -XPOST"
  local request="curl $curl_options $distribution_url/api/v1/export/release_bundle/$release_bundle_name/$release_bundle_version"
  $request
}

__deleteExportedBundle() {
  local curl_options=$distribution_curl_options
  curl_options+=" -XDELETE"
  local request="curl $curl_options $distribution_url/api/v1/export/release_bundle/$release_bundle_name/$release_bundle_version"
  $request
}

__downloadReleaseBundle() {
  local curl_options=$distribution_curl_options
  curl_options+=" -XGET"
  local request="curl $curl_options $download_url"
  $request
}

__handleExportStatus() {
  export_status=$1
  should_cleanup_export=false
  # Trigger release bundle export if possible
  if [ "$export_status" == "NOT_TRIGGERED" ] || [ "$export_status" == "FAILED" ]; then
    execute_command "echo 'Exporting Release Bundle: $release_bundle_name/$release_bundle_version'"
    local export_http_code
    export_http_code=$(exportReleaseBundle)
    if [ "$export_http_code" -ne 202 ]; then
      execute_command "echo Failed to export release bundle -- status $export_http_code"
      execute_command "cat $resp_body_file"
      execute_command "exit 1"
    fi
    execute_command "echo 'Started export of Release Bundle $release_bundle_name}/$release_bundle_version}'"
    should_cleanup_export=true
  fi
  echo $should_cleanup_export
}

__isReleaseBundleExporting() {
  local status
  status=$(cat $resp_body_file | jq -r .status)
  if [ "$status" == "IN_PROGRESS" ] ||
   [ "$status" == "NOT_EXPORTED" ]; then
    return
  fi
  false
}

downloadBuildInfo() {
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
}

downloadReleaseBundle() {
  # Export and download release bundle
  local release_bundle_res_name=$(get_resource_name --type ReleaseBundle --operation IN)
  release_bundle_version=$(eval echo "$"res_"$release_bundle_res_name"_version)
  release_bundle_name=$(eval echo "$"res_"$release_bundle_res_name"_name)
  distribution_url=$(eval echo "$"res_"$release_bundle_res_name"_sourceDistribution_url)
  distribution_user=$(eval echo "$"res_"$release_bundle_res_name"_sourceDistribution_user)
  distribution_apikey=$(eval echo "$"res_"$release_bundle_res_name"_sourceDistribution_apikey)
  distribution_curl_options="--silent --retry 3 --write-out %{http_code}\n --output $resp_body_file -u $distribution_user:$distribution_apikey"
  if [ "$no_verify_ssl" == "true" ]; then
    distribution_curl_options+=" --insecure"
  fi

  # Check if release bundle was already exported
  local status_http_code=$(__getDistributionExportStatus)

  # exit on bad response codes
  if [ "$status_http_code" -ne 200 ]; then
    execute_command "echo 'Could not get Release Bundle export status'"
    execute_command "echo http status: $status_http_code"
    execute_command "exit 1"
  fi

  # Possible values: IN_PROGRESS|FAILED|NOT_TRIGGERED|NOT_EXPORTED|COMPLETED
  local export_status=$(cat "$resp_body_file" | jq -r .status)

  # Export the Release Bundle if hasn't yet been
  local should_cleanup_export=$(__handleExportStatus "$export_status")

  if [ "$export_status" == "FAILED" ]; then
    execute_command "echo 'Release bundle export Failed'"
    execute_command "exit 1"
  fi

  # Wait for export to finish
  status_http_code=$(__getDistributionExportStatus)
  local sleeperCount=2
  while [ "$status_http_code" -lt 299 ] && [ "$(__isReleaseBundleExporting)" = true ]; do
    execute_command "sleep $sleeperCount"
    sleeperCount+="$sleeperCount"
    if [ $sleeperCount -gt 64 ]; then
      # Keep checking for 128 seconds if export status hasn't reached COMPLETED yet
      break
    fi
    status_http_code=$(__getDistributionExportStatus)
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
  # download release bundle
  local download_url=$(echo "$resp_body" | jq -r .download_url)
  status_http_code=$(__downloadReleaseBundle "$download_url")

  # exit on bad response codes
  if [ "$status_http_code" -ne 200 ]; then
    execute_command "echo 'Could not get Release Bundle export status'"
    execute_command "echo http status: $status_http_code"
    execute_command "exit 1"
  fi
  execute_command "echo 'Downloaded Release Bundle $release_bundle_name/$release_bundle_version successfully'"

  execute_command "unzip $resp_body_file"

  if [ "$should_cleanup_export" = true ]; then
    execute_command "echo 'Deleting Release Bundle export: $release_bundle_name/$release_bundle_version'"
    delete_http_code="$(__deleteExportedBundle)"
    # exit on bad response codes
    if [ "$delete_http_code" -ne 200 ]; then
      execute_command "echo 'Could not get Release Bundle export status'"
      execute_command "echo http status: $delete_http_code"
      execute_command "exit 1"
    fi
  fi
}
