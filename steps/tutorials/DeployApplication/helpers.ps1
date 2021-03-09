function setupSSH($key_name) {
  $ssh_key_path = Join-Path $env:USERPROFILE -ChildPath ".ssh" | Join-Path -ChildPath $key_name
  execute_command "Get-Service -Name ssh-agent | Set-Service -StartupType Manual"
  execute_command "Start-Service ssh-agent"
  execute_command "ssh-add $ssh_key_path"
}

class ReleaseBundleDownloader {
  [string]$BundleVersion
  [string]$BundleName
  [string]$Url
  [string]$ResponseBodyFile
  [hashtable]$AuthHeaders
  [bool]$ShouldCleanupExport
  [string]$CommonRequestParams

  ReleaseBundleDownloader([string]$resourceName) {
    $this.BundleVersion = $( (Get-Variable -Name "res_$( $resourceName )_version").Value )
    $this.BundleName = $( (Get-Variable -Name "res_$( $resourceName )_name").Value )
    $this.Url = $( (Get-Variable -Name "res_$( $resourceName )_sourceDistribution_url").Value )
    $user = $( (Get-Variable -Name "res_$( $resourceName )_sourceDistribution_user").Value )
    $apikey = $( (Get-Variable -Name "res_$( $resourceName )_sourceDistribution_apikey").Value )
    $encodedAuth = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${global:distribution_user}:${global:distribution_apikey}"))
    $this.AuthHeaders = @{ Authorization = "Basic $encodedAuth" }
    $this.ShouldCleanupExport = $false
    $this.ResponseBodyFile = "${global:step_tmp_dir}/response"
#    $this.CommonRequestParams = "$($this.AuthHeaders) -TimeoutSec 60 -UseBasicParsing -OutFile `"$($this.ResponseBodyFile)`" -PassThru"
  }

  Download() {
    # Release bundle must be exported before it can be downloaded
    execute_command "echo 'starting download'"
    $downloadUrl = $this._ensureExport()
    execute_command "echo 'Release Bundle $($this.BundleName)/$($this.BundleVersion) is exported'"
    $this._download($downloadUrl)
  }

  _download($downloadUrl) {
    execute_command "retry_command Invoke-WebRequest ${downloadURL} -Method Get $($this.CommonRequestParams)"
    execute_command "echo 'Downloaded Release Bundle $($this.BundleName)/$($this.BundleVersion)'"
    execute_command "unzip $($this.ResponseBodyFile)"
  }

  # Returns a download url once export is done
  [string]
  _ensureExport() {
    $exportStatus = $this._getDistributionExportStatus()
    if ($exportStatus -eq "NOT_TRIGGERED" -or $exportStatus -eq "FAILED") {
      $this.ShouldCleanupExport = $true
      $exportStatus = $this._exportReleaseBundle()
      if ($exportStatus -eq "FAILED") {
        execute_command "throw `"Release Bundle export failed"`"
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
      $exportStatus = $this._getDistributionExportStatus()
    }

    if ($exportStatus -ne "COMPLETED") {
      execute_command "throw 'Failed to export release bundle with export status: ${exportStatus}'"
    }

    return (ConvertFrom-JSON (Get-Content $this.ResponseBodyFile)).download_url
  }

  [string]
  _exportReleaseBundle() {
    execute_command "Write-Output 'Exporting Release Bundle: $($this.BundleName)/$($this.BundleVersion)'"
    execute_command "retry_command Invoke-WebRequest `"$(this.Url)/api/v1/export/release_bundle/$($this.BundleName)/$($this.BundleVersion)`" -Method Post -Headers -ContentType 'application/json' $($this.CommonRequestParams)"
    $exportStatus = (ConvertFrom-JSON (Get-Content "${global:step_tmp_dir}/response")).status
    return $exportStatus
  }

  [string]
  _getDistributionExportStatus() {
    execute_command "retry_command Invoke-WebRequest `"$($this.Url)/api/v1/export/release_bundle/$($this.BundleName)/$($this.BundleVersion)/status`" -Method Get $($this.CommonRequestParams)"
    $exportStatus = (ConvertFrom-JSON (Get-Content "$($this.ResponseBodyFilePath)")).status
    return $exportStatus
  }
}
