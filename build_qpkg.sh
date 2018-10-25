#!/bin/bash

#############################################################################
# QDK in the docker
QDK_DOCKER_USERNAME=qeekdev
QDK_DOCKER_NAME=qdk-docker
QDK_DOCKER_VERSION=2.3.4-apim
QDK_DOKCER_IMAGE="${QDK_DOCKER_USERNAME}/${QDK_DOCKER_NAME}:${QDK_DOCKER_VERSION}"

#############################################################################
local_path=`pwd`
QPKG_NAME="helloqpkg"
# working directory for collect the source of each repo and qdk build root
WORKING=${local_path}/working
# staging directory that collect all qpkg and qdk files in the qpkg build time
WORKING_QPKG_ROOT=${WORKING}/${QPKG_NAME}
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

function log_err_exit()
{
  echo "${RED} [X] [$(date '+%Y/%m/%d %H:%M:%S')] $@ ${RESET}"
  exit 1
}

function exec_err {
  "$@"
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
  rm -rf ${WORKING_QPKG_ROOT} &> /dev/null
  exec_err mkdir -p ${WORKING_QPKG_ROOT}
  exec_err cp -r ${local_path}/qpkg/. ${WORKING_QPKG_ROOT}/
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

# install the helloqpkg program to qpkg working directory
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
    "helloqpkg-backend"

  # deploy frontend program
  exec_err cp -r ${local_path}/src/web ${WORKING_QPKG_ROOT}/shared

  # deploy qpkg asset
  exec_err cp -r ${local_path}/src/asset/qpkg/. ${WORKING_QPKG_ROOT}/

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

  docker run $BUILDER_OPTS $QDK_DOKCER_IMAGE bash -c "\
    cd /root/tmp/working/${QPKG_NAME} && \
    qbuild --build-arch ${CPU_ARCH} --build-version ${QPKG_VERSION} && \
    mv /root/tmp/working/${QPKG_NAME}/build/${QPKG_NAME}_${QPKG_VERSION}_${CPU_ARCH}.qpkg \
        /root/tmp/release/${QPKG_FILE}.qpkg && \
    mv /root/tmp/working/${QPKG_NAME}/build/${QPKG_NAME}_${QPKG_VERSION}_${CPU_ARCH}.qpkg.md5 \
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
  local SHORT_QPKG="helloqpkg.qpkg"
  [ ! -f "$QPKG_FILE" ] && log_err_exit "missing qpk file to install to NAS ($RHOST)"
  [ ! -z "$3" ] && SSHPASS_CMD="sshpass -p $3"

  ${SSHPASS_CMD} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $QPKG_FILE admin@$RHOST:/share/Public/${SHORT_QPKG}
  ${SSHPASS_CMD} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t admin@$RHOST "export LANG=en_US.UTF-8 ; export LC_ALL=en_US.UTF-8 ; export LANGUAGE=en_US.UTF-8 ; qpkg_cli -D 2 -m /share/Public/$SHORT_QPKG ; sleep 3"
  log "[ $FUNCNAME $@ ] done ..."
}


function build_qpkg() {
  log "[ $FUNCNAME $@ ] start ..."
  CPU_ARCH=${1}
  QPKG_VERSION=${2}
  NAS_IP=${3}
  NAS_PASSWD=${4}

  init_qdk_working
  build_source "${CPU_ARCH}"
  compile_qpkg "${CPU_ARCH}" "${QPKG_VERSION}"

  if [ ! -z "${NAS_IP}" ]; then
    # get last qpkg file name by modify time.
    gen_file=`ls ${WORKING_QPKG_DIST}/*${CPU_ARCH}*.qpkg | sort -r | head -1`
    install_qpkg ${gen_file} ${NAS_IP} ${NAS_PASSWD}
  else
    log_info "missing param \$3 nas ip.. skip install qpkg"
  fi
  log "[ $FUNCNAME $@ ] done ..."
}


function requirements() {
  command -v docker >/dev/null 2>&1 || log_err_exit "Require \"docker\" but it's not installed.  Aborting."
  command -v git >/dev/null 2>&1 || log_err_exit "Require \"git\" but it's not installed.  Aborting."
  git submodule update --init QDK
  if [[ "$(docker images -q ${QDK_DOKCER_IMAGE} 2>/dev/null)" == "" ]]; then
    docker build -t ${QDK_DOKCER_IMAGE}.buildstage -f ./qdk-docker/Dockerfile.build-stage .
    docker build -t ${QDK_DOKCER_IMAGE} -f ./qdk-docker/Dockerfile.run-time .
  fi
}
##################################################################################################

log "*** build qpkg ${1} start. ***"

if [ $# -eq 0 ]; then
  echo ""
  echo ""
  echo "./${0} {CPU_ARCH} {QPKG_VERSION} {NAS_IP} {NAS_PASSWD}"
  echo "ex: ./${0} x86_64 0.1 192.168.0.10 passw0rd"
  echo "CPU_ARCH: x86_64, arm_64, arm-x41, arm-x31 ..."
  echo ""
  echo ""
  exit 1
fi

requirements
build_qpkg "${1}" "${2}" "${3}" "${4}"

log "*** build qpkg ${1} done. ***"

