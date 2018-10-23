#!/bin/bash

RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
MAGENTA=`tput setaf 5`
RESET=`tput sgr0`

local_path=`pwd`
QPKG_NAME="helloqpkg"
# working directory for collect the source of each repo and qdk build root
WORKING=${local_path}/working
# staging directory that collect all qpkg and qdk files in the qpkg build time
WORKING_QPKG_ROOT=${WORKING}/workspace/${QPKG_NAME}
# the build of qpkg file after qbuild in the container
WORKING_QPKG_DIST=${WORKING}/release_qpkg

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

# install the helloqpkg program to qpkg working directory
function build_source() {
  log "[ $FUNCNAME $@ ] start ..."

  exec_err cp -r ${local_path}/source/app ${WORKING_QPKG_ROOT}/shared/
  exec_err cp -r ${local_path}/source/web ${WORKING_QPKG_ROOT}/shared/

  log "[ $FUNCNAME $@ ] done ..."
}

function compile_qpkg() {
  # the ${QPKG_FILE} will be generated in the ${WORKING_QPKG_DIST}
  log "[ $FUNCNAME $@ ] start ..."

  cd ${local_path}
  local _qpkg_build_num=`git rev-list HEAD --count`

  cd ${WORKING}
  local _build_revision="${_qpkg_build_num}"

  # save source code revision and arch into qpkg
  echo -n "$_build_revision" > ${WORKING_QPKG_ROOT}/shared/.revision
  echo -n "${CPU_ARCH}" > ${WORKING_QPKG_ROOT}/shared/.qpkg_arch

  local BUILD_DATE=`date +"%Y%m%d%H%M"`
  local CPU_ARCH=$1
  local QPKG_VERSION=${2}
  local QPKG_FILE="${QPKG_NAME}_${QPKG_VERSION}_${CPU_ARCH}_${BUILD_DATE}"

  local BUILDER_USERNAME=qeekdev
  local BUILDER_NAME=qdk-docker
  local BUILDER_VERSION=2.3.4-apim
  local BUILDER_DOKCER="${BUILDER_USERNAME}/${BUILDER_NAME}:${BUILDER_VERSION}"
  local HOSTDIR=${WORKING}
  local CONTAINER_NAME=${BUILDER_NAME}-`date +%s`
  local BUILDER_OPTS="\
      --net=host \
      --rm \
      -e PNAME=${BUILDER_NAME}-$1-builder-`date +%s` \
      -e \"TZ=Asia/Taipei\" \
      -u root \
      -w /root \
      -v ${HOSTDIR}:/root/working \
      --name=${CONTAINER_NAME}"

  docker run $BUILDER_OPTS $BUILDER_DOKCER bash -c "\
    cd /root/working/workspace/${QPKG_NAME} && \
    qbuild --build-arch ${CPU_ARCH} --build-version ${QPKG_VERSION} && \
    mv /root/working/workspace/${QPKG_NAME}/build/${QPKG_NAME}_${QPKG_VERSION}_${CPU_ARCH}.qpkg \
        /root/working/release_qpkg/${QPKG_FILE}.qpkg && \
    mv /root/working/workspace/${QPKG_NAME}/build/${QPKG_NAME}_${QPKG_VERSION}_${CPU_ARCH}.qpkg.md5 \
        /root/working/release_qpkg/${QPKG_FILE}.qpkg.md5 \
    "
  [ $? != "0" ] && log_err_exit "build qpkg fail"
  log_info "QPKG here => ./working/release_qpkg/$QPKG_FILE.qpkg"
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


function _build_() {
  log "[ $FUNCNAME $@ ] start ..."
  CPU_ARCH=${1}
  QPKG_VERSION=${2}
  NAS_IP=${3}
  NAS_PASSWD=${4}

  init_qdk_working
  build_source
  compile_qpkg "${CPU_ARCH}" "${QPKG_VERSION}"

  if [ ! -z "${NAS_IP}" ]; then
    # get last qpkg file name by modify time.
    gen_file=`ls ${WORKING_QPKG_DIST}/*.qpkg | sort -r | head -1`
    install_qpkg ${gen_file} ${NAS_IP} ${NAS_PASSWD}
  else
    log_info "missing param \$3 nas ip.. skip install qpkg"
  fi
  log "[ $FUNCNAME $@ ] done ..."
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

_build_ "${1}" "${2}" "${3}" "${4}"

log "*** build qpkg ${1} done. ***"

