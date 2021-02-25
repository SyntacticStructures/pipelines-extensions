function DeployApplication() {
  #  gci env:* | sort-object name
   Set-Content -Path "${PWD}\id_rsa" -Value $res_myVM_sshKey_privateKey
  cat .\id_rsa
  ssh -i .\id_rsa -n 192.168.50.3 "ls"
#  $vmcluster_res_name = $(get_resource_name -type VmCluster -operation "IN")
#  $vm_targets = $((Get-Variable -Name "res_$($vmcluster_res_name)_targets").Value | ConvertFrom-Json)
#
#  $buildinfo_res_name = $(get_resource_name -type BuildInfo -operation "IN")
#  $filespec_res_name = $(get_resource_name -type FileSpec -operation "IN")
#  $releasebundle_res_name = $(get_resource_name -type ReleaseBundle -operation "IN")
#
#  # TODO: validate number of resources
#
#
#  $tardir="${PWD}\work"
#  mkdir $tardir
#
#  if ($buildinfo_res_name -ne "") {
#    $buildinfo_number = $((Get-Variable -Name "res_$($buildinfo_res_name)_buildNumber").Value)
#    $buildinfo_name = $((Get-Variable -Name "res_$($buildinfo_res_name)_buildName").Value)
#    $buildinfo_rt_url = $((Get-Variable -Name "res_$($buildinfo_res_name)_sourceArtifactory_url").Value)
#    $buildinfo_rt_user = $((Get-Variable -Name "res_$($buildinfo_res_name)_sourceArtifactory_user").Value)
#    $buildinfo_rt_apiKey = $((Get-Variable -Name "res_$($buildinfo_res_name)_sourceArtifactory_apikey").Value)
#
#    execute_command "jfrog rt dl `"*`" $tardir\ --build=$buildinfo_name/$buildinfo_number --url=$buildinfo_rt_url --user=$buildinfo_rt_user --password=$buildinfo_rt_apikey  --insecure-tls"
#  } elseif ($filespec_res_name -ne "") {
#    $filespec_res_path = $((Get-Variable -Name "res_$($filespec_res_name)_resourcePath").Value)
#    echo "this should not happen"
#    exit 1
#  }
#
#  foreach ($vm_target in $vm_targets) {
#
#  }
}

execute_command DeployApplication
