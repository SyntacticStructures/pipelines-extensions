function DeployApplication() {
#  gci env:* | sort-object name
  $buildinfo_res_name = $(get_resource_name -type BuildInfo -operation "IN")
  $vm_cluster_name = $(get_resource_name -type VmCluster -operation "IN")

  $vm_targets=$((Get-Variable -Name "res_$($vm_cluster_name)_targets").Value | ConvertFrom-Json)
  echo $vm_targets[0]
}

execute_command DeployApplication
