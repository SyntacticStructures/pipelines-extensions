deployApplication() {
  echo "finding resource..."
  ls $res_myApp_resourcePath
  cat $res_myApp_resourcePath/myApp.sh
  echo $res_myVM_publicKey
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
