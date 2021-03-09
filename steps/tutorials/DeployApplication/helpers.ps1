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
  [string]$ResponseFilePath
  [string]$AuthHeaders
  [bool]$SouldCleanupExport

  ReleaseBundleDownloader([string]$resource_name) {
    $this.BundleVersion = $( (Get-Variable -Name "res_$( $releasebundle_res_name )_version").Value )
    $this.BundleName = $( (Get-Variable -Name "res_$( $releasebundle_res_name )_name").Value )
    $this.Url = $( (Get-Variable -Name "res_$( $releasebundle_res_name )__sourceDistribution_url").Value )
    $user = $( (Get-Variable -Name "res_$( $releasebundle_res_name )__sourceDistribution_user").Value )
    $apikey = $( (Get-Variable -Name "res_$( $releasebundle_res_name )__sourceDistribution_apikey").Value )
    $encodedAuth = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${distribution_user}:${distribution_apikey}"))
    $this.AuthHeaders = @{ Authorization = "Basic $encodedAuth" }
    $this.SouldCleanupExport = $false
    $this.ResponseFilePath = "${step_tmp_dir}/response"
  }

  Download() {
    $exportStatus = $this.getDistributionExportStatus
    if ($status -eq "NOT_TRIGGERED" -or $status -eq "FAILED") {
      $this.SouldCleanupExport = $true
      $exportStatus = $this.exportReleaseBundle
      if ($exportStatus -eq "FAILED") {
        execute_command "throw `"Release Bundle export failed"`"
      }
    }

    sleepSeconds = 2
    while ("$jobStatus" -eq "NOT_EXPORTED" -or "$jobStatus" -eq "IN_PROGRESS") {
      execute_command "echo 'Waiting for release bundle export to complete'"
      execute_command "Start-Sleep -Seconds $sleeperCount"
      if ($sleepSeconds -gt 64) {
        # 128s timeout
        break
      }
    }

  }

  [string]
  exportReleaseBundle() {
    execute_command "Write-Output 'Exporting Release Bundle: ${this.BundleName}/${this.BundleVersion}'"
    execute_command "retry_command Invoke-WebRequest `"${this.Url}/api/v1/export/release_bundle/${this.BundleName}/${this.BundleVersion}`" -Method Post -Headers `$this.AuthHeaders -TimeoutSec 60 -ContentType 'application/json' -UseBasicParsing -OutFile `"`${this.ResponseFilePath}`" -PassThru"
    try {
      $exportStatus = (ConvertFrom-JSON (Get-Content "${step_tmp_dir}/response")).status
    }
    catch {
      execute_command "throw `"Failed to parse export Release Bundle status with error: $_`""
    }
    return $exportStatus
  }

  [string]
  getDistributionExportStatus() {
    execute_command "retry_command Invoke-WebRequest `"${this.Url}/api/v1/export/release_bundle/${this.BundleName}/${this.BundleVersion}/status`" -Method Get -Headers `$this.AuthHeaders -TimeoutSec 60 -UseBasicParsing -OutFile `"`${this.ResponseFilePath}`" -PassThru"
    try {
      $exportStatus = (ConvertFrom-JSON (Get-Content "${this.ResponseFilePath}")).status
    }
    catch {
      execute_command "throw `"Failed to parse export Release Bundle status with error: $_`""
    }
    return $exportStatus
  }
}

function downloadReleaseBundle($release_bundle_res_name) {
  $release_bundle_version = $( (Get-Variable -Name "res_$( $releasebundle_res_name )_version").Value )
  $release_bundle_name = $( (Get-Variable -Name "res_$( $releasebundle_res_name )_name").Value )
  $distribution_url = $( (Get-Variable -Name "res_$( $releasebundle_res_name )__sourceDistribution_url").Value )
  $distribution_user = $( (Get-Variable -Name "res_$( $releasebundle_res_name )__sourceDistribution_user").Value )
  $distribution_apikey = $( (Get-Variable -Name "res_$( $releasebundle_res_name )__sourceDistribution_apikey").Value )
  $should_cleanup_export = $false

  $encoded_auth = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${distribution_user}:${distribution_apikey}"))
  $headers = @{ }
  $headers['Authorization'] = "Basic $encoded_auth"

  $response = Invoke-WebRequest -URI

}
