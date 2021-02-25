function DeployApplication() {
#  gci env:* | sort-object name
  $vmcluster_res_name = $(get_resource_name -type VmCluster -operation "IN")
  $vm_targets = $((Get-Variable -Name "res_$($vmcluster_res_name)_targets").Value | ConvertFrom-Json)

  $buildinfo_res_name = $(get_resource_name -type BuildInfo -operation "IN")
  $filespec_res_name = $(get_resource_name -type FileSpec -operation "IN")
  $releasebundle_res_name = $(get_resource_name -type ReleaseBundle -operation "IN")

  # TODO: validate number of resources


  $tardir="${PWD}/work"
  mkdir $tardir

  if ($buildinfo_res_name -ne "") {
    echo "trying"
    $buildinfo_number = $((Get-Variable -Name "res_$($buildinfo_res_name)_buildNumber").Value)
    $buildinfo_name = $((Get-Variable -Name "res_$($buildinfo_res_name)_buildName").Value)
    $buildinfo_rt_url = $((Get-Variable -Name "res_$($buildinfo_res_name)_sourceArtifactory_url").Value)
    $buildinfo_rt_user = $((Get-Variable -Name "res_$($buildinfo_res_name)_sourceArtifactory_user").Value)
    $buildinfo_rt_apiKey = $((Get-Variable -Name "res_$($buildinfo_res_name)_sourceArtifactory_apikey").Value)
    echo $buildinfo_rt_url
    echo $buildinfo_rt_user
    echo $buildinfo_rt_apiKey
    execute_command "jfrog rt dl \"*\" $tardir/ --build=$buildinfo_name/buildinfo_number --url=$buildinfo_rt_url --user=$buildinfo_rt_user --apikey=$buildinfo_rt_apikey"

    ls $tardir
  } elseif ($filespec_res_name -ne "") {
    $filespec_res_path = $((Get-Variable -Name "res_$($filespec_res_name)_resourcePath").Value)
    echo "oh crap"
  }


}

DeployApplication
