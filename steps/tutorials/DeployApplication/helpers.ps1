function setupSSH($key_name) {
  $ssh_key_path = Join-Path $env:USERPROFILE -ChildPath ".ssh" | Join-Path -ChildPath $key_name
  execute_command "Get-Service -Name ssh-agent | Set-Service -StartupType Manual"
  execute_command "Start-Service ssh-agent"
  execute_command "ssh-add $ssh_key_path"
}



function DownloadReleaseBundle($resourceName) {
  _inner
}

function _inner() {
  _inner2
}
function _inner2() {
  execute_command "echo 'hello'"
}
