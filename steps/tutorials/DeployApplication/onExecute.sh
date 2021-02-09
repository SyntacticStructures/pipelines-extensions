deployApplication() {
  # TODO: install rsync on imageBuilds
  apt-get install -y rsync

  local ip_addr=$(jq "$res_myVM_targets"[0] --raw-output --null-input)
  local ssh_id="$HOME/.ssh/myVM"

  rsync -e "ssh -i $ssh_id" "$res_myApp_resourcePath" "$ip_addr":"$step_configuration_targetDirectory"
  ssh -i "$ssh_id" "$step_configuration_deployCommand"

  echo "deployApplication running"
}

execute_command deployApplication
