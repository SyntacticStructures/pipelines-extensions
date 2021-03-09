function setupSSH($key_name) {
  $ssh_key_path = Join-Path $env:USERPROFILE -ChildPath ".ssh" | Join-Path -ChildPath $key_name
  execute_command "Get-Service -Name ssh-agent | Set-Service -StartupType Manual"
  execute_command "Start-Service ssh-agent"
  execute_command "ssh-add $ssh_key_path"
}



function DownloadReleaseBundle($resourceName) {
  $script:BundleVersion = $( (Get-Variable -Name "res_$( $resourceName )_version").Value )
  $script:BundleName = $( (Get-Variable -Name "res_$( $resourceName )_name").Value )
  $script:Url = $( (Get-Variable -Name "res_$( $resourceName )_sourceDistribution_url").Value )
  $script:user = $( (Get-Variable -Name "res_$( $resourceName )_sourceDistribution_user").Value )
  $script:apikey = $( (Get-Variable -Name "res_$( $resourceName )_sourceDistribution_apikey").Value )
  $script:EncodedAuth = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${user}:${apikey}"))
  $script:ShouldCleanupExport = $false
  $script:ResponseBodyFile = "${env:step_tmp_dir}\response"
  $script:ZipResponseBodyFile = "${env:step_tmp_dir}\response.zip"
  $script:CommonRequestParams = "-TimeoutSec 60 -UseBasicParsing -PassThru"
  _downloadReleaseBundle
}

function _downloadReleaseBundle() {
  # Release bundle must be exported before it can be downloaded
  execute_command "echo 'starting download'"
  execute_command "echo $BundleVersion"
  $downloadUrl = _ensureExport
  execute_command "echo 'Release Bundle ${BundleName}/${BundleVersion} is exported'"
  $headers = @{ Authorization = "Basic ${EncodedAuth}" }
  execute_command "echo 'Downloading Release Bundle ${BundleName}/${BundleVersion}'"
  execute_command "retry_command Invoke-WebRequest `"${downloadURL}`" -Method Get -Headers `$headers ${CommonRequestParams} -OutFile ${ZipResponseBodyFile}"
  Expand-Archive -LiteralPath $ZipResponseBodyFile -DestinationPath $PWD
}

function _ensureExport() {
  execute_command "echo '_ensureExport'"
  $exportStatus = _getDistributionExportStatus
  if ($exportStatus -eq "NOT_TRIGGERED" -or $exportStatus -eq "FAILED") {
    $ShouldCleanupExport = $true
    $exportStatus = _exportReleaseBundle
    if ($exportStatus -eq "FAILED") {
      execute_command "throw 'Release Bundle export failed'"
    }
  }

  $sleepSeconds = 2
  while ("$exportStatus" -eq "NOT_EXPORTED" -or "$exportStatus" -eq "IN_PROGRESS") {
    execute_command "echo 'Waiting for release bundle export to complete'"
    execute_command "Start-Sleep -Seconds ${sleepSeconds}"
    if ($sleepSeconds -gt 64) {
      # 128s timeout
      break
    }
    $exportStatus = _getDistributionExportStatus
  }

  if ($exportStatus -ne "COMPLETED") {
    execute_command "throw 'Failed to export release bundle with export status: ${exportStatus}'"
  }

  return (ConvertFrom-JSON (Get-Content $ResponseBodyFile)).download_url
}

function _exportReleaseBundle() {
  $headers = @{ Authorization = "Basic ${EncodedAuth}" }
  execute_command "Write-Output 'Exporting Release Bundle: ${BundleName}/${BundleVersion}'"
  execute_command "retry_command Invoke-WebRequest `"${Url}/api/v1/export/release_bundle/${BundleName}/${BundleVersion}`" -Method Post -Headers `$headers -ContentType 'application/json' -OutFile ${ResponseBodyFile} ${CommonRequestParams}"
  $exportStatus = (ConvertFrom-JSON (Get-Content $ResponseBodyFile)).status
  return $exportStatus
}

function _getDistributionExportStatus() {
  $headers = @{ Authorization = "Basic ${EncodedAuth}" }
  execute_command "retry_command Invoke-WebRequest `"$Url/api/v1/export/release_bundle/${BundleName}/${BundleVersion}/status`" -Method Get -Headers `$headers -OutFile ${ResponseBodyFile} ${CommonRequestParams}"
  $exportStatus = (ConvertFrom-JSON (Get-Content $ResponseBodyFile)).status
  return $exportStatus
}
