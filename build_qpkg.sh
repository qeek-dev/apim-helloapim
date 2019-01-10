#!/bin/bash

#############################################################################
# QDK in the docker
QDK_DOCKER_USERNAME=qeekdev
QDK_DOCKER_NAME=qdk-docker
QDK_DOCKER_VERSION=2.3.4-apim
QDK_DOKCER_IMAGE="${QDK_DOCKER_USERNAME}/${QDK_DOCKER_NAME}:${QDK_DOCKER_VERSION}"

#############################################################################
local_path=`pwd`
QPKG_NAME="helloapim"
# working directory for collect the source of each repo and qdk build root
WORKING=${local_path}/working
# staging directory of QDK source code
WORKING_QDK_ROOT=${WORKING}/QDK
# staging directory that collect all qpkg files
WORKING_QPKG_ROOT=${WORKING_QDK_ROOT}/${QPKG_NAME}
# the build of qpkg file after qbuild in the container
WORKING_QPKG_DIST=${local_path}/release

#############################################################################
# Log text with color in the terminal
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
MAGENTA=`tput setaf 5`
RESET=`tput sgr0`

function log()
{
  echo "${GREEN} [V] [$(date '+%Y/%m/%d %H:%M:%S')] $@ ${RESET}"
}

function log_info()
{
  echo "${YELLOW} [I] [$(date '+%Y/%m/%d %H:%M:%S')] $@ ${RESET}"
}

function log_err()
{
  echo "${RED} [X] [$(date '+%Y/%m/%d %H:%M:%S')] $@ ${RESET}"
}

function log_warn()
{
  echo "${MAGENTA} [W] [$(date '+%Y/%m/%d %H:%M:%S')] $@ ${RESET}"
}

function log_err_exit()
{
  echo "${RED} [X] [$(date '+%Y/%m/%d %H:%M:%S')] $@ ${RESET}"
  exit 1
}

function exec_err {
  "$@" #>/dev/null 2>&1
  status=$?
  if [ $status -ne 0 ]; then
    log_err "ERROR: Encountered error (${status}) while running the following:" >&2
    log_err "           $@"  >&2
    log_err "       (at line ${BASH_LINENO[0]} of file $0.)"  >&2
    log_err "       Aborting." >&2
    exit $status
  fi
}

# prepare working directory for mount in the qdk container
# note: qpkg file generates in the ${WORKING}/release_qpkg/
function init_qdk_working() {
  log "[ $FUNCNAME $@ ] start ..."

  [ ! -d "${WORKING_QPKG_DIST}" ] && exec_err mkdir -p ${WORKING_QPKG_DIST}
  # reset the qpkg source workspace folder for building time.
  # prepare for mount in the container.
  rm -rf ${WORKING_QDK_ROOT} >/dev/null 2>&1
  rm -rf ${WORKING_QPKG_ROOT} >/dev/null 2>&1

  # QDK program
  exec_err mkdir -p ${WORKING_QDK_ROOT}
  exec_err cp -r ${local_path}/QDK/shared/. ${WORKING_QDK_ROOT}/

  # QPKG template
  exec_err mkdir -p ${WORKING_QPKG_ROOT}
  exec_err cp -r ${local_path}/QDK/shared/template/. ${WORKING_QPKG_ROOT}/
  log "[ $FUNCNAME $@ ] done ..."
}

function _build_backend_server() {
  log "[ $FUNCNAME $@ ] start ..."


  local CPU_ARCH=$1
  local SOURCE_DIR=$2
  local DIST_DIR=$3
  local DIST_FILENAME=$4
  local GOLANG_DOKCER_IMAGE=golang:1.11.1-alpine3.8
  local CONTAINER_NAME=golang-1.11.1-builder-`date +%s`
  local BUILDER_OPTS="\
      --net=host \
      --rm \
      -e \"TZ=Asia/Taipei\" \
      -u root \
      -w /go \
      -v ${SOURCE_DIR}:/go/src/server \
      -v ${DIST_DIR}:/root/dist \
      --name=${CONTAINER_NAME}"

  case "$CPU_ARCH" in
    arm_64)
      GOARCH=arm64
      ;;
    arm-x19|arm-x31|arm-x41)
      GOARCH=arm
      ;;
    x86|x86_ce53xx)
      GOARCH=386
      ;;
    x86_64)
      GOARCH=amd64
      ;;
  esac

  docker run $BUILDER_OPTS $GOLANG_DOKCER_IMAGE sh -c "\
    apk add --no-cache --virtual git && \
    cd /go/src/server && \
    export GO111MODULE=on && \
    go mod download && \
    CGO_ENABLED=0 GOOS=linux GOARCH=${GOARCH} go build -a -tags netgo -ldflags \"-s -w\" -o /root/dist/${DIST_FILENAME} .
  "
  [ $? != "0" ] && log_err_exit "[ $FUNCNAME $@ ] fail ..."
  log "[ $FUNCNAME $@ ] done ..."
}

# build and install the program to qdk working directory
function build_source() {
  log "[ $FUNCNAME $@ ] start ..."
  local CPU_ARCH=$1
  # deploy qpkg start script
  exec_err cp -r ${local_path}/src/init.d/. ${WORKING_QPKG_ROOT}/shared/

  # complie & deploy backend program
  exec_err mkdir -p ${WORKING_QPKG_ROOT}/shared/server
  _build_backend_server \
    "${CPU_ARCH}" \
    "${local_path}/src/server" \
    "${WORKING_QPKG_ROOT}/shared/server" \
    "${QPKG_NAME}-backend"

  # deploy frontend program
  exec_err cp -r ${local_path}/src/web ${WORKING_QPKG_ROOT}/shared

  # deploy qpkg asset
  exec_err cp -r ${local_path}/src/asset/qpkg/. ${WORKING_QPKG_ROOT}/

  log "[ $FUNCNAME $@ ] done ..."
}

# encrypt apim json by sr-cli in the remote NAS that install with apim qpkg.
function build_apim_json() {
  log "[ $FUNCNAME $@ ] start ..."
  local _ip=${1}
  local _sshpass="sshpass -p $2"
  local _sshparam="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  local _apim_json="${local_path}/src/asset/apim/apim.json"
  local _md5sum="md5"
  command -v ${_md5sum} >/dev/null 2>&1 || _md5sum="md5sum"
  local _uuid=$(date | ${_md5sum} | head -c8)
  local _tmp_json="apim${_uuid}.json"

  if [ ! -f "${_apim_json}" ]; then
    log_err_exit "Not found \"./src/asset/apim/apim.json\"."
  fi

  exec_err ${_sshpass} scp ${_sshparam} \
    $_apim_json admin@${_ip}:/share/Public/${_tmp_json}

  exec_err ${_sshpass} ssh ${_sshparam} \
    -t admin@${_ip} "cd /share/Public/ && /usr/local/apim/bin/sr-cli encrypt ${_tmp_json} && cat ${_tmp_json}"

  exec_err ${_sshpass} scp ${_sshparam} \
    admin@${_ip}:/share/Public/${_tmp_json}.enc ${WORKING_QPKG_ROOT}/shared/apim.json.enc

  exec_err ${_sshpass} ssh ${_sshparam} \
    -t admin@${_ip} "rm /share/Public/${_tmp_json} && rm /share/Public/${_tmp_json}.enc"

  log "[ $FUNCNAME $@ ] done ..."
}

function compile_qpkg() {
  # the ${QPKG_FILE} will be generated in the ${WORKING_QPKG_DIST}
  log "[ $FUNCNAME $@ ] start ..."

  cd ${local_path}
  local _qpkg_build_num=`git rev-list HEAD --count`
  local _build_revision="${_qpkg_build_num}"

  # save source code revision and arch into qpkg
  echo -n "$_build_revision" > ${WORKING_QPKG_ROOT}/shared/.revision
  echo -n "${CPU_ARCH}" > ${WORKING_QPKG_ROOT}/shared/.qpkg_arch

  local BUILD_DATE=`date +"%Y%m%d%H%M"`
  local CPU_ARCH=$1
  local QPKG_VERSION=${2}
  local QPKG_FILE="${QPKG_NAME}_${QPKG_VERSION}_${CPU_ARCH}_${BUILD_DATE}"
  local HOSTDIR=${local_path}
  local CONTAINER_NAME=${QDK_DOCKER_NAME}-`date +%s`
  local BUILDER_OPTS="\
      --net=host \
      --rm \
      -e \"TZ=Asia/Taipei\" \
      -u root \
      -w /root \
      -v ${HOSTDIR}:/root/tmp \
      --name=${CONTAINER_NAME}"

  # install QDK each time for make sure it is latest.
  docker run $BUILDER_OPTS $QDK_DOKCER_IMAGE bash -c "\
    cd /root/tmp/working/QDK/${QPKG_NAME} && \
    fakeroot ../bin/qbuild --build-arch ${CPU_ARCH} --build-version ${QPKG_VERSION} && \
    mv /root/tmp/working/QDK/${QPKG_NAME}/build/${QPKG_NAME}_${QPKG_VERSION}_${CPU_ARCH}.qpkg \
        /root/tmp/release/${QPKG_FILE}.qpkg && \
    mv /root/tmp/working/QDK/${QPKG_NAME}/build/${QPKG_NAME}_${QPKG_VERSION}_${CPU_ARCH}.qpkg.md5 \
        /root/tmp/release/${QPKG_FILE}.qpkg.md5 \
    "
  [ $? != "0" ] && log_err_exit "[ $FUNCNAME $@ ] fail ..."
  log_info "QPKG here => ./release/$QPKG_FILE.qpkg"
  log "[ $FUNCNAME $@ ] done ..."
}


# $1 QPKG_FILE, $2 NAS_IP $3 PASSWORD
function install_qpkg() {
  log "[ $FUNCNAME $@ ] start ..."
  local QPKG_FILE=$1
  local RHOST=$2
  local SHORT_QPKG="${QPKG_NAME}.qpkg"
  [ ! -f "$QPKG_FILE" ] && log_err_exit "missing qpk file to install to NAS ($RHOST)"
  [ ! -z "$3" ] && SSHPASS_CMD="sshpass -p $3"

  ${SSHPASS_CMD} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $QPKG_FILE admin@$RHOST:/share/Public/${SHORT_QPKG} >/dev/null 2>&1
  ${SSHPASS_CMD} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -t admin@$RHOST "export LANG=en_US.UTF-8 ; export LC_ALL=en_US.UTF-8 ; export LANGUAGE=en_US.UTF-8 ; qpkg_cli -D 2 -m /share/Public/$SHORT_QPKG ; sleep 3" >/dev/null 2>&1
  log "[ $FUNCNAME $@ ] done ..."
}


function build_qpkg() {
  log "[ $FUNCNAME $@ ] start ..."
  local CPU_ARCH=${1}
  local NAS_IP=${2}
  local NAS_PASSWD=${3}
  local QPKG_VERSION=${4}

  if [[ ${QPKG_VERSION} == "" ]]; then
    QPKG_VERSION=$(dev_version)
  fi

  log_info "QPKG_VERSION: ${QPKG_VERSION}"

  init_qdk_working
  build_apim_json "${NAS_IP}" "${NAS_PASSWD}"
  build_source "${CPU_ARCH}"
  compile_qpkg "${CPU_ARCH}" "${QPKG_VERSION}"

  if [ ! -z "${NAS_IP}" ]; then
    # get last qpkg file name by modify time.
    gen_file=`ls ${WORKING_QPKG_DIST}/${QPKG_NAME}*${CPU_ARCH}*.qpkg | sort -r | head -1`
    install_qpkg ${gen_file} ${NAS_IP} ${NAS_PASSWD}
  else
    log_info "missing param \$3 nas ip.. skip install qpkg"
  fi
  log "[ $FUNCNAME $@ ] done ..."
}


function check_command() {
  command -v $1 >/dev/null 2>&1 || log_err_exit "Require \"$1\" but it's not installed.  Aborting."
}

function requirements() {
  check_command docker
  check_command git
  check_command ssh
  check_command scp
  check_command sshpass

  git submodule update --init QDK
  # build the qdk docker image
  if [[ "$(docker images -q ${QDK_DOKCER_IMAGE} 2>/dev/null)" == "" ]]; then
    # build stage that make the "qpkg_encrypt" for run time qdk docker.
    docker build -t ${QDK_DOKCER_IMAGE}.buildstage -f ./qdk-docker/Dockerfile.build-stage .
    # the run time qdk docker image
    docker build -t ${QDK_DOKCER_IMAGE} -f ./qdk-docker/Dockerfile.run-time .
  fi
}
##################################################################################################

function dev_version() {
  cd ${local_path}
  local _core_build_num=`git rev-list HEAD --count`
  cd ${local_path}/QDK
  local _qdk_build_num=`git rev-list HEAD --count`

  local _res="0.${_core_build_num}.${_qdk_build_num}"
  echo $_res
}

log "*** build qpkg ${1} start. ***"

if [ $# -eq 0 ]; then
  echo ""
  echo ""
  echo "./${0} {CPU_ARCH} {NAS_IP} {NAS_PASSWD} {QPKG_VERSION} "
  echo "ex: ./${0} x86_64 192.168.0.10 passw0rd 0.1"
  echo "  if no {QPKG_VERSION}, will generate a dev verison number. "
  echo "ex: ./${0} x86_64 192.168.0.10 passw0rd"
  echo "CPU_ARCH: x86_64, arm_64, arm-x41, arm-x31 ..."
  echo ""
  echo ""
  exit 1
fi


requirements
build_qpkg "${1}" "${2}" "${3}" "${4}"

log "*** build qpkg ${1} done. ***"

