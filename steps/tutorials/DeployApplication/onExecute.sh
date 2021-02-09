deployApplication() {
  printenv
#  scp -i ~/.ssh/myVM "$res_myApp_resourcePath" $(jq -n $res_myVM_targets[0]):/opt/
  ls "$res_myApp_resourcePath"
  local ip_addr=$(jq $res_myVM_targets[0] --raw-output --null-input)
  ls ~/.ssh
  rsync -e "ssh -i ~/.ssh/u16ssh" "$res_myApp_resourcePath"/myApp.sh "$ip_addr":/opt/
#  local success=true
#  local url=$(find_step_configuration_value "healthCheckUrl")
#  {
#    local statusCode=$(curl --silent --output /dev/stderr --write-out "%{http_code}" "$url")
#  } || exitCode=$?
#  if test $statusCode -ne 200; then
#    export success=false
#    echo "Health check failed with statusCode: $statusCode & exitCode: $exitCode for url: $url"
#  else
#    echo "Health check succeeded"
#  fi

  echo "deployApplication running"
}

execute_command deployApplication
