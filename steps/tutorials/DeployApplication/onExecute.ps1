function DeployApplication() {
  $buildinfo_res_name = $(get_resource_name -type BuildInfo -operation "IN")
  $buildinfo_number = "res_$($buildinfo_res_name)_buildNumber"
  $buildinfo_name = "res_$($buildinfo_res_name)_buildName"

  $filespec_res_name = $(get_resource_name -type FileSpec -operation "IN")
  $filespec_res_path = "res_$($filespec_res_name)_resourcePath"

  $releasebundle_res_name = $(get_resource_name -type ReleaseBundle -operation "IN")

  $vmcluster_res_name = $(get_resource_name -type VmCluster -operation "IN")
  $vm_targets = $((Get-Variable -Name "res_$($vmcluster_res_name)_targets").Value | ConvertFrom-Json)

  echo $buildinfo_res_name
  echo $vmcluster_res_name

  if ($buildinfo_res_name -ne $null) {
    echo "res name"
    echo $buildinfo_res_name
  }

  if ($filespec_res_name -ne $null) {
    echo "well crap"
  }
}

execute_command DeployApplication
