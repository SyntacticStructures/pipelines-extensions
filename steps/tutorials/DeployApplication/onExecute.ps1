$ErrorActionPreference = "Stop"

# TODO: implement $DEPLOY_TARGETS_OVERRIDE

function SetupSSH($key_name) {
  $ssh_key_path = Join-Path $env:USERPROFILE -ChildPath ".ssh" | Join-Path -ChildPath $key_name
  execute_command "Get-Service -Name ssh-agent | Set-Service -StartupType Manual"
  execute_command "Start-Service ssh-agent"
  execute_command "ssh-add $ssh_key_path"
}

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

  SetupSSH($vmcluster_res_name)

  $tardir = Join-Path $PWD -ChildPath "uploadFiles"
  execute_command "mkdir $tardir"

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

    $ssh_base_cmd = "ssh $step_configuration_sshUser@2.tcp.ngrok.io -p 19002 -o StrictHostKeyChecking=no"

    # Command to upload app tarball to vm
    $upload_command = "scp -P 19002 -o StrictHostKeyChecking=no .\$tarball_name $step_configuration_sshUser@2.tcp.ngrok.io`:$step_configuration_targetDirectory"

    # Command to run the deploy command from within the uploaded dir
    $untar = "cd $step_configuration_targetDirectory/; tar -xvf $tarball_name; rm -f $tarball_name;"
    $deploy_command = "$ssh_base_cmd `"$untar $step_configuration_deployCommand`""

    # Command to run after the deploy command from within the uploaded dir
    $post_deploy_command = "$ssh_base_cmd `"cd $step_configuration_targetDirectory; $step_configuration_postDeployCommand`""

    try {
      execute_command $upload_command
      execute_command $deploy_command
      if ($step_configuration_postDeployCommand -ne $null) {
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

DeployApplication
