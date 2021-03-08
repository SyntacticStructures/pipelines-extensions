$ErrorActionPreference = "Stop"

# TODO: implement $DEPLOY_TARGETS_OVERRIDE
. .\helpers.ps1

function DeployApplication() {
  #  gci env:* | sort-object name
  $vmcluster_res_name = $( get_resource_name -type VmCluster -operation "IN" )
  $vm_targets = $( (Get-Variable -Name "res_$( $vmcluster_res_name )_targets").Value | ConvertFrom-Json )

  $buildinfo_res_name = $( get_resource_name -type BuildInfo -operation "IN" )
  $filespec_res_name = $( get_resource_name -type FileSpec -operation "IN" )
  $releasebundle_res_name = $( get_resource_name -type ReleaseBundle -operation "IN" )

  $deployable_resources = @($buildinfo_res_name, $filespec_res_name, $releasebundle_res_name).Where({ $_.Length })

  if (@($deployable_resources).Length -ne 1) {
    execute_command "throw `"Exactly one resource of type BuildInfo`|ReleaseBundle`|FileSpec is supported.`""
  }

  setupSSH($vmcluster_res_name)

  $tardir = Join-Path $PWD -ChildPath "uploadFiles"
  execute_command "mkdir $tardir"

  # Create a file with env vars to source on the target vms
  $vm_env_filename="$step_name-$run_id.env"
  $vm_env_file_path="$tardir\$vm_env_filename"
  if ($step_configuration_vmEnvironmentVariables_len -ne $null) {
    execute_command "echo we have env vars"
    for ($i=0; $i -lt $step_configuration_vmEnvironmentVariables_len; $i++) {
      $env_var = $ExecutionContext.InvokeCommand.ExpandString(
        $( (Get-Variable -Name "step_configuration_vmEnvironmentVariables_$( $i )").Value )
      )
      execute_command "echo $env_var"
      Add-Content -Path $vm_env_file_path -Value "export $env_var"
    }
    execute_command "cat $vm_env_file_path"
  }

  pushd $tardir
    if ($buildinfo_res_name -ne "") {
      $buildinfo_number = $( (Get-Variable -Name "res_$( $buildinfo_res_name )_buildNumber").Value )
      $buildinfo_name = $( (Get-Variable -Name "res_$( $buildinfo_res_name )_buildName").Value )
      $buildinfo_rt_url = $( (Get-Variable -Name "res_$( $buildinfo_res_name )_sourceArtifactory_url").Value )
      $buildinfo_rt_user = $( (Get-Variable -Name "res_$( $buildinfo_res_name )_sourceArtifactory_user").Value )
      $buildinfo_rt_apiKey = $( (Get-Variable -Name "res_$( $buildinfo_res_name )_sourceArtifactory_apikey").Value )

      execute_command "retry_command jfrog rt dl `"*`" $tardir\ --build=$buildinfo_name/$buildinfo_number --url=$buildinfo_rt_url --user=$buildinfo_rt_user --password=$buildinfo_rt_apikey  --insecure-tls"
    }
    elseif ($filespec_res_name -ne "") {
      $filespec_res_path = $( (Get-Variable -Name "res_$( $filespec_res_name )_resourcePath").Value )
      execute_command "mv $filespec_res_path\* $tardir"
    }
    elseif ($releasebundle_res_name -ne "") {
      $release_bundle_version=$( (Get-Variable -Name "res_$( $releasebundle_res_name )_version").Value )
      $release_bundle_name=$( (Get-Variable -Name "res_$( $releasebundle_res_name )_name").Value )
      $distribution_url=$( (Get-Variable -Name "res_$( $releasebundle_res_name )__sourceDistribution_url").Value )
      $distribution_user=$( (Get-Variable -Name "res_$( $releasebundle_res_name )__sourceDistribution_user").Value )
      $distribution_apikey=$( (Get-Variable -Name "res_$( $releasebundle_res_name )__sourceDistribution_apikey").Value )
    }
    $tarball_name = "$pipeline_name-$run_id.tar.gz"
    execute_command "tar -czvf ../$tarball_name ."
  popd

  # TODO -- IMPORTANT: do not hard-code vm addrs
  for ($i = 0; $i -lt $vm_targets.Length; $i++) {
    $vm_target = $vm_targets[$i]

    if ($step_configuration_rolloutDelay -ne $null -and $i -ne 0) {
      execute_command "Start-Sleep -s $step_configuration_rolloutDelay"
    }

    $ssh_base_cmd = "ssh $step_configuration_sshUser@4.tcp.ngrok.io -p 12061 -o StrictHostKeyChecking=no"

    $target_dir="~/$step_name/$run_id"
    if ($step_configuration_targetDirectory -ne $null) {
      $target_dir=$step_configuration_targetDirectory
    }
    $make_target_dir_command = "$ssh_base_cmd `"mkdir -p $target_dir`""

    # Command to upload app tarball to vm
    $upload_command = "scp -P 12061 -o StrictHostKeyChecking=no .\$tarball_name $step_configuration_sshUser@4.tcp.ngrok.io`:$target_dir"

    # Command to source the file with vmEnvironmentVariables
    if ($step_configuration_vmEnvironmentVariables_len -ne $null) {
      source_env_file="source $target_dir/$vm_env_filename;"
    }

    # Command to run the deploy command from within the uploaded dir
    $untar = "cd $target_dir/; tar -xvf $tarball_name; rm -f $tarball_name;"
    $deploy_command = "$ssh_base_cmd `"$untar $source_env_file $step_configuration_deployCommand`""

    # Command to run after the deploy command from within the uploaded dir
    $post_deploy_command = "$ssh_base_cmd `"cd $target_dir; $source_env_file $step_configuration_postDeployCommand`""

    try {
      execute_command "echo Creating target dir on vm"
      execute_command $make_target_dir_command

      execute_command "echo Uploading artifacts to vm"
      execute_command $upload_command

      execute_command "echo Running deploy command"
      execute_command $deploy_command
      if ($step_configuration_postDeployCommand -ne $null) {
        execute_command "echo Running post-deploy command"
        execute_command $post_deploy_command
      }
    }
    catch {
      # Don't exit on failed commands if fastFail is specified as false
      if ($step_configuration_fastFail -eq $false) {
        continue
      }
      throw
    }
  }
}

execute_command DeployApplication
