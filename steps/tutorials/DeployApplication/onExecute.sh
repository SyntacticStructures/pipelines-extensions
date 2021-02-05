deployApplication() {
  echo "eval..."
  echo "add"
  echo "ssh add done"
  ls ~/.ssh
  echo ~/.ssh/myVM
  echo $res_myVM_targets
  echo "hey" >> file.txt
  echo "created file"
  scp -i ~/.ssh/myVM "$res_myApp_path/$res_myApp_name" 192.168.50.19:/opt/
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
