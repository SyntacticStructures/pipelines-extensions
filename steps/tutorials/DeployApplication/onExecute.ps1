function DeployApplication() {
  gci env:* | sort-object name
  $buildinfo_res_name = $(get_resource_name -type BuildInfo -operation "IN")
  $vm_cluster_name = $(get_resource_name -type VmCluster -operation "IN")

  echo $buildinfo_res_name
  echo $vm_cluster_name
}

execute_command DeployApplication
