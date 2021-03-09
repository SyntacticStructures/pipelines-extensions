$ErrorActionPreference = "Stop"

execute_command ". .\helpers.ps1"

function testfunc() {
  execute_command "echo 'hello'"
}

. .\helpers.ps1
function DeployApplication() {
  #  gci env:* | sort-object name
  $vmClusterResName = $( get_resource_name -type VmCluster -operation "IN" )
  $vmTargets = $( (Get-Variable -Name "res_$( $vmClusterResName )_targets").Value | ConvertFrom-Json )

  $buildinfoResName = $( get_resource_name -type BuildInfo -operation "IN" )
  $filespecResName = $( get_resource_name -type FileSpec -operation "IN" )
  $releasebundle_res_name = $( get_resource_name -type ReleaseBundle -operation "IN" )

  $deployableResources = @($buildinfoResName, $filespecResName, $releasebundle_res_name).Where({ $_.Length })

  if (@($deployableResources).Length -ne 1) {
    execute_command "throw `"Exactly one resource of type BuildInfo`|ReleaseBundle`|FileSpec is supported.`""
  }

  if ("$DEPLOY_TARGETS_OVERRIDE" -ne $null) {
    execute_command "echo 'Overriding vm deploy targets with: $DEPLOY_TARGETS_OVERRIDE'"
    $vmTargets = $DEPLOY_TARGETS_OVERRIDE.Split(",")
  }

  setupSSH($vmClusterResName)

  $tardir = Join-Path $PWD -ChildPath "uploadFiles"
  execute_command "mkdir ${tardir}"

  # Create a file with env vars to source on the target vms
  $vmEnvFilename = "${step_name}-${run_id}.env"
  $vmEnvFilePath = "${tardir}\${vmEnvFilename}"
  if ($step_configuration_vmEnvironmentVariables_len -ne $null) {
    for ($i = 0; $i -lt $step_configuration_vmEnvironmentVariables_len; $i++) {
      $envVar = $ExecutionContext.InvokeCommand.ExpandString(
          $( (Get-Variable -Name "step_configuration_vmEnvironmentVariables_$( $i )").Value )
      )
      Add-Content -Path $vmEnvFilePath -Value "export ${envVar}"
    }
    # TODO delete this cat
    execute_command "cat $vmEnvFilePath"
  }

  pushd $tardir
  if ($buildinfoResName -ne "") {
    $buildinfoNumber = $( (Get-Variable -Name "res_$( $buildinfoResName )_buildNumber").Value )
    $buildinfoName = $( (Get-Variable -Name "res_$( $buildinfoResName )_buildName").Value )
    $buildinfoURL = $( (Get-Variable -Name "res_$( $buildinfoResName )_sourceArtifactory_url").Value )
    $buildinfoUser = $( (Get-Variable -Name "res_$( $buildinfoResName )_sourceArtifactory_user").Value )
    $buildinfoApikey = $( (Get-Variable -Name "res_$( $buildinfoResName )_sourceArtifactory_apikey").Value )
    execute_command "retry_command jfrog rt dl `"*`" ${tardir}\ --build=${buildinfoName}/${buildinfoNumber} --url=${buildinfoURL} --user=${buildinfoUser} --password=${buildinfoApikey} --insecure-tls"
  }
  elseif ($filespecResName -ne "") {
    $filespecResPath = $( (Get-Variable -Name "res_$( $filespecResName )_resourcePath").Value )
    execute_command "mv $filespecResPath\* $tardir"
  }
  elseif ($releasebundle_res_name -ne "") {
    execute_command "echo 'we are here'"
    $releaseBundleDownloader = [ReleaseBundleDownloader]::new($releasebundle_res_name)
    execute_command "echo 'we are there'"
    try {
      $releaseBundleDownloader.Download()
    } catch {
      execute_command "echo error"
      execute_command "echo $_"
    }

    execute_command "echo 'we are done'"
  }
  $tarballName = "${pipeline_name-$run_id}.tar.gz"
  execute_command "tar -czvf ../${tarballName} ."
  popd

  # TODO -- IMPORTANT: do not hard-code vm addrs
  $failedVMs = @()
  for ($i = 0; $i -lt $vmTargets.Length; $i++) {
    $vmTarget = $vmTargets[$i]

    if ($step_configuration_rolloutDelay -ne $null -and $i -ne 0) {
      execute_command "Start-Sleep -s $step_configuration_rolloutDelay"
    }

    $sshBaseCmd = "ssh ${step_configuration_sshUser}@0.tcp.ngrok.io -p 19176 -o StrictHostKeyChecking=no"

    $targetDir = "~/${step_name}/${run_id}"
    if ($step_configuration_targetDirectory -ne $null) {
      $targetDir = $step_configuration_targetDirectory
    }
    $makeTargetDirCommand = "${sshBaseCmd} `"mkdir -p ${targetDir}`""

    # Command to upload app tarball to vm
    $uploadCommand = "scp -P 19176 -o StrictHostKeyChecking=no .\${tarballName} ${step_configuration_sshUser}@0.tcp.ngrok.io`:${targetDir}"

    # Command to source the file with vmEnvironmentVariables
    if ($step_configuration_vmEnvironmentVariables_len -ne $null) {
      $sourceEnvFile = "source ${targetDir}/${vmEnvFilename};"
    }

    # Command to run the deploy command from within the uploaded dir
    $untar = "cd ${targetDir}/; tar -xvf ${tarballName}; rm -f ${tarballName};"
    $deployCommand = "${sshBaseCmd} `"${untar} ${sourceEnvFile} ${step_configuration_deployCommand}`""

    # Command to run after the deploy command from within the uploaded dir
    $postDeployCommand = "${sshBaseCmd} `"cd ${targetDir}; ${sourceEnvFile} ${step_configuration_postDeployCommand}`""

    try {
      execute_command "echo Creating target dir on vm"
      execute_command $makeTargetDirCommand

      execute_command "echo Uploading artifacts to vm"
      execute_command $uploadCommand

      execute_command "echo Running deploy command"
      execute_command $deployCommand
      if ($step_configuration_postDeployCommand -ne $null) {
        execute_command "echo Running post-deploy command"
        execute_command $postDeployCommand
      }
    }
    catch {
      $failedVMs += $vmTarget

      # Don't exit on failed commands if fastFail is specified as false
      if ($step_configuration_fastFail -eq $false) {
        continue
      }
      break
    }

    # Deploy was successful.

    $rollbackDir = "~/${step_name}/rollback"
    # Command to copy artifacts into rollback dir.
    $createRollbackArtifacts = "${sshBaseCommand} `"mkdir -p ${rollbackDir}; rm -rf ${rollbackDir}/*; cp -r ${targetDir}/* ${rollbackDir}`""
    execute_command "echo 'Archiving successful deploy for rollback'"
    execute_command "${createRollbackArtifacts}"
  }

  # Do rollback
  if (($step_configuration_rollbackCommand -ne $null) -and ($failedVMs.count -gt 0)) {
    Foreach ($vmTarget IN $vmTargets) {
      execute_command "echo 'Executing rollback command on vm: ${vmTarget}'"
      # TODO -- IMPORTANT: do not hard-code vm addrs
      $sshBaseCmd = "ssh ${step_configuration_sshUser}@4.tcp.ngrok.io -p 12061 -o StrictHostKeyChecking=no"
      try {
        execute_command "${sshBaseCommand} `"${step_configuration_rollbackCommand}`""
      }
      catch {
        # Ignore failures and try to rollback the next vm
        continue
      }
    }
  }
}

function check_no_verify_ssl() {
  if ($no_verify_ssl -eq "true") {
    if (-not([System.Management.Automation.PSTypeName]"TrustEverything").Type) {
      Add-Type -TypeDefinition  @"
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
public static class TrustEverything
{
  private static bool ValidationCallback(object sender, X509Certificate certificate, X509Chain chain,
    SslPolicyErrors sslPolicyErrors) { return true; }
  public static void SetCallback() { System.Net.ServicePointManager.ServerCertificateValidationCallback = ValidationCallback; }
  public static void UnsetCallback() { System.Net.ServicePointManager.ServerCertificateValidationCallback = null; }
}
"@
    }
    [TrustEverything]::SetCallback()
  }
}

check_no_verify_ssl
execute_command "DeployApplication"
