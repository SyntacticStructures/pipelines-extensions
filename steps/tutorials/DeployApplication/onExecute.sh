deployApplication() {
  eval `ssh-agent`
  ssh-add -k
  echo $res_myVM_publicKey
  cat test.txt
  echo $res_myVM_name
  echo $res_myVM_targets
  echo "hey" >> file.txt
  scp -v ./file.txt 192.168.50.19:/opt/file.txt
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

#  $success
  echo "deployApplication running"
}

execute_command deployApplication
