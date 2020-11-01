#!/usr/bin/env bash

# Setup script environment
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap cleanup EXIT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  exit $EXIT
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}
function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}
# set -x

parrent_path=$(pwd)

NAME=${1:-"Testing"}
LXC_BASE_DIR="/var/lib/lxc"

LXC_CONFIG=${NAME}.lxc.config

if [[ -f $LXC_CONFIG ]]; then
	rm -rf $LXC_CONFIG 2&>/dev/null
fi

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null


cat > $LXC_CONFIG <<-"EOF"
	# The lxc_rootfs_mount is injected when lxc.hook.mount OR lxc.hook.autodev is run!
	# lxc.environment = LXC_ROOTFS_MOUNT=<LXC_BASE_DIR>/<NAME>/rootfs

	##Issue with apt-get! Must not add this? Think NOT
	#lxc.arch = x86_64
	## Or need to copy the /usr/bin/qemu-x86_64 to container (/usr/bin) first? NO


	lxc.net.0.type = veth
	lxc.net.0.flags = up
	lxc.net.0.hwaddr = 00:16:3E:3B:8B:7C
	lxc.net.0.link = bridge0

	## Bellow activated does "KILL" apt-get ie. errors with Permissions etc.
	## https://github.com/whiskerz007/proxmox_hassio_lxc/blob/fad821e2c3d2d0fb570f844379f03b247ff3b9c7/create_container.sh#L141
	#lxc.cgroup.devices.allow = a
	#lxc.cap.drop = 

	## https://github.com/whiskerz007/proxmox_hassio_lxc/blob/fad821e2c3d2d0fb570f844379f03b247ff3b9c7/create_container.sh#L148
	# lxc.hook.pre-start = "sh -ec 'for module in aufs overlay; do modinfo $module; $(lsmod | grep -Fq $module) || modprobe $module; done;'"

	## https://github.com/whiskerz007/proxmox_hassio_lxc/blob/fad821e2c3d2d0fb570f844379f03b247ff3b9c7/create_container.sh#L156
	lxc.hook.mount = "sh -c 'ln -fs $(readlink /etc/localtime) LXC_ROOTFS/etc/localtime'"
EOF

# The lxc_rootfs_mount is injected when lxc.hook.mount OR lxc.hook.autodev is run!
# sed -i "s/<NAME>/$NAME/g" ${LXC_CONFIG}
# sed -i "s|<LXC_BASE_DIR>|$LXC_BASE_DIR|g" ${LXC_CONFIG}

cp ${LXC_CONFIG} ${parrent_path}

msg "Moved config: $(pwd)/${LXC_CONFIG} to: ${parrent_path}"
