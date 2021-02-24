function DeployApplication() {
#  gci env:* | sort-object name
  $buildinfo_res_name = $(get_resource_name -type BuildInfo -operation "IN")
  $vm_cluster_name = $(get_resource_name -type VmCluster -operation "IN")

  echo $buildinfo_res_name

  echo $vm_cluster_name

  $res_targets="res_$($vm_cluster_name)_targets"
  echo $res_targets
  echo $($res_targets)
}

execute_command DeployApplication
