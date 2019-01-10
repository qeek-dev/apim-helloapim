#!/bin/bash
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
MAGENTA=`tput setaf 5`
RESET=`tput sgr0`

function log()
{
  echo "${GREEN} [V] [$(date '+%Y/%m/%d %H:%M:%S')] $@ ${RESET}"
}

function log_err()
{
  echo "${RED} [X] [$(date '+%Y/%m/%d %H:%M:%S')] $@ ${RESET}"
}

function log_err_exit()
{
  echo "${RED} [X] [$(date '+%Y/%m/%d %H:%M:%S')] $@ ${RESET}"
  exit 1
}

if [ $# -eq 0 ]; then
  echo "${0} {NAS_IP}"
  echo "ex: ${0} 192.168.0.10"
  exit 1
fi

NAS_IP=$1
REQUEST_URL="http://${NAS_IP}:13000/v1/record/1"

curl -s -X POST ${REQUEST_URL} -d '{"hello1":"world"}' -H "Content-Type: application/json" 1>/dev/null 2>/dev/null
if [ $? == 0 ]; then
    log "POST ${REQUEST_URL} -d '{\"hello1\":\"world\"}', success."
else
    log_err_exit "POST ${REQUEST_URL} -d '{\"hello1\":\"world\"}', failed"
fi

data=$(curl -s -X GET ${REQUEST_URL} -H "Content-Type: application/json")
if [ $? == 0 ]; then
    log "GET ${REQUEST_URL}, result: $data"
else
    log_err_exit "GET ${REQUEST_URL}, failed"
fi
