#!/usr/bin/env bash

# Setup script environment
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
# trap cleanup EXIT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
#  info "Environment was:"
  env
  info "Going to clean up and exit with $EXIT"
  [ ! -z ${CTID-} ] && cleanup_ctid
  exit $EXIT
}
function warn() {
  local REASON="\e[97m$1\e[39m"
  local FLAG="\e[93m[WARNING]\e[39m"
  msg "$FLAG $REASON"
}
function info() {
  local REASON="$1"
  local FLAG="\e[36m[INFO]\e[39m"
  msg "$FLAG $REASON"
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}
 function cleanup_ctid() {
   if $(lxc-info $CTID &>/dev/null); then
     if [ "$(lxc-info $CTID | awk '{print $2}')" == "running" ]; then
       lxc-stop $CTID
     fi
     lxc-destroy $CTID
#   elif [ "$(pvesm list $STORAGE --vmid $CTID)" != "" ]; then
#     pvesm free $ROOTFS
   fi
 }
function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}
TEMP_DIR=$(mktemp -d)
cp *.sh $TEMP_DIR

pushd $TEMP_DIR >/dev/null

info "Workingdirectory is: $(pwd)"
info "Content: 
$(ls -l)"

# Download setup script
## REPO="https://github.com/whiskerz007/proxmox_hassio_lxc"
## wget -qO - ${REPO}/tarball/master | tar -xz --strip-components=1

# # Select storage location
# while read -r line; do
#   TAG=$(echo $line | awk '{print $1}')
#   TYPE=$(echo $line | awk '{printf "%-10s", $2}')
#   FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
#   ITEM="  Type: $TYPE Free: $FREE "
#   OFFSET=2
#   if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
#     MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
#   fi
#   STORAGE_MENU+=( "$TAG" "$ITEM" "OFF" )
# done < <(pvesm status -content rootdir | awk 'NR>1')
# 
# if [ $((${#STORAGE_MENU[@]}/3)) -eq 0 ]; then
#   warn "'Container' needs to be selected for at least one storage location."
#   die "Unable to detect valid storage location."
# elif [ $((${#STORAGE_MENU[@]}/3)) -eq 1 ]; then
#   STORAGE=${STORAGE_MENU[0]}
# else
#   while [ -z "${STORAGE:+x}" ]; do
#     STORAGE=$(whiptail --title "Storage Pools" --radiolist \
#     "Which storage pool you would like to use for the container?\n\n" \
#     16 $(($MSG_MAX_LENGTH + 23)) 6 \
#     "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3) || exit
#   done
# fi
# info "Using '$STORAGE' for storage location."

# Get the next guest VM/LXC ID
# CTID=$(pvesh get /cluster/nextid)

CTID=${1:-Testing}
info "Container ID is: '$CTID'"

OSTYPE=debian
OSVERSION=buster

msg "Setup target container config..."
bash ./setup_lxc_config.sh $CTID


CONFIG="$(pwd)/${CTID}.lxc.config"
# ARCH=x86_64
# ARCH="$(arch)"
ARCH=amd64
# ARCH=arm64

LXC_OPTIONS=(
	-n $CTID 
	-t download 
	-B best 
	-f $CONFIG 
	--  
	--dist=$OSTYPE
	--arch=$ARCH
	--release=$OSVERSION
)

if [[ ! -f ${CONFIG} ]]; then
	echo "Missing LXC config: '$CONFIG'"
	EXIT=1 LINE=$LINENO error_exit 
	exit 1
fi


msg "Create container..."
echo "CMD.  : 'lxc-create ${LXC_OPTIONS[@]}'"
echo "CONFIG: "
cat "${CONFIG}"
lxc-create ${LXC_OPTIONS[@]} 


export LXC_BASE=/var/lib/lxc
export CT_BASE="${LXC_BASE}/${CTID}"
export LXC_ROOTFS_MOUNT="${CT_BASE}/rootfs/"

##### Temp DISABLED
#msg "Patch container config to enable nesting..."
#sed -i 's/^#lxc.include/lxc.include/' "${CT_BASE}/config"

# Set autodev hook to enable access to devices in container
##### Temp DISABLED
#msg "Setting up the autodev hook script..."
#bash ./set_autodev_hook.sh $CTID


info "Updated config content:"
cat ${CT_BASE}/config || EXIT=1 LINE=$LINENO error_exit



# # Load modules for Docker before starting LXC
# cat << 'EOF' >> $LXC_CONFIG
# lxc.hook.pre-start: sh -ec 'for module in aufs overlay; do modinfo $module; $(lsmod | grep -Fq $module) || modprobe $module; done;'
# EOF


# # Set container timezone to match host
# cat << 'EOF' >> $LXC_CONFIG
# lxc.hook.mount: sh -c 'ln -fs $(readlink /etc/localtime) ${LXC_ROOTFS_MOUNT}/etc/localtime'
# EOF

# Setup container for Home Assistant
msg "Starting LXC container..."
#pct start $CTID
lxc-start -n ${CTID} --logpriority=debug --logfile=${LXC_BASE}/${CTID}/${CTID}.log

### Begin LXC commands ###
alias lxc-cmd="lxc-attach -n $CTID --"
# Prepare container OS
msg "Setting up container OS..."
lxc-cmd dhclient -4
lxc-cmd sed -i "s/\(^en_US.UTF-8\)/# \1/" /etc/locale.gen
lxc-cmd sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
lxc-cmd locale-gen >/dev/null
lxc-cmd apt-get -y purge openssh-{client,server} >/dev/null

# Update container OS
msg "Updating container OS..."
lxc-cmd apt-get update >/dev/null
lxc-cmd apt-get -qqy upgrade &>/dev/null


# Install prerequisites
msg "Installing prerequisites..."
lxc-cmd apt-get -qqy install \
    wget kmod avahi-daemon curl jq network-manager xterm &>/dev/null


echo "*********************** Early exit ***********************"
exit 0


# Install Docker
msg "Installing Docker..."
lxc-cmd sh <(curl -sSL https://get.docker.com) &>/dev/null

# Configure Docker configuration
msg "Configuring Docker..."
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
HA_URL_BASE=https://github.com/home-assistant/supervised-installer/raw/master/files
lxc-cmd mkdir -p $(dirname $DOCKER_CONFIG_PATH)
lxc-cmd wget -qLO $DOCKER_CONFIG_PATH ${HA_URL_BASE}/docker_daemon.json
lxc-cmd systemctl restart docker

# Configure NetworkManager
msg "Configuring NetworkManager..."
NETWORKMANAGER_CONFIG_PATH='/etc/NetworkManager/NetworkManager.conf'
lxc-cmd wget -qLO $NETWORKMANAGER_CONFIG_PATH ${HA_URL_BASE}/NetworkManager.conf
lxc-cmd sed -i 's/type\:veth/interface-name\:veth\*/' $NETWORKMANAGER_CONFIG_PATH
lxc-cmd dhclient -r &> /dev/null
lxc-cmd systemctl restart NetworkManager
lxc-cmd nm-online -q

# Create Home Assistant config
msg "Creating Home Assistant config..."
HASSIO_CONFIG_PATH=/etc/hassio.json
HASSIO_DOCKER=homeassistant/amd64-hassio-supervisor
HASSIO_MACHINE=qemux86-64
HASSIO_DATA_PATH=/usr/share/hassio
lxc-cmd bash -c "cat > $HASSIO_CONFIG_PATH <<- EOF
{
    \"supervisor\": \"${HASSIO_DOCKER}\",
    \"machine\": \"${HASSIO_MACHINE}\",
    \"data\": \"${HASSIO_DATA_PATH}\"
}
EOF
"

# Pull Home Assistant Supervisor image
msg "Downloading Home Assistant Supervisor container..."
HASSIO_VERSION=$(lxc-cmd bash -c "curl -s https://version.home-assistant.io/stable.json | jq -e -r '.supervisor'")
lxc-cmd docker pull "$HASSIO_DOCKER:$HASSIO_VERSION" > /dev/null
lxc-cmd docker tag "$HASSIO_DOCKER:$HASSIO_VERSION" "$HASSIO_DOCKER:latest" > /dev/null

# Install Home Assistant Supervisor
msg "Installing Home Assistant Supervisor..."
HASSIO_SUPERVISOR_PATH=/usr/sbin/hassio-supervisor
HASSIO_SUPERVISOR_SERVICE=/etc/systemd/system/hassio-supervisor.service
lxc-cmd wget -qLO $HASSIO_SUPERVISOR_PATH ${HA_URL_BASE}/hassio-supervisor
lxc-cmd chmod a+x $HASSIO_SUPERVISOR_PATH
lxc-cmd wget -qLO $HASSIO_SUPERVISOR_SERVICE ${HA_URL_BASE}/hassio-supervisor.service
lxc-cmd sed -i "s,%%HASSIO_CONFIG%%,${HASSIO_CONFIG_PATH},g" $HASSIO_SUPERVISOR_PATH
lxc-cmd sed -i -e "s,%%BINARY_DOCKER%%,/usr/bin/docker,g" \
  -e "s,%%SERVICE_DOCKER%%,docker.service,g" \
  -e "s,%%BINARY_HASSIO%%,${HASSIO_SUPERVISOR_PATH},g" \
  $HASSIO_SUPERVISOR_SERVICE
lxc-cmd systemctl enable hassio-supervisor.service > /dev/null 2>&1

# Create service to fix Home Assistant boot time check
msg "Creating service to fix boot time check..."
pct push $CTID hassio-fix-btime.service /etc/systemd/system/hassio-fix-btime.service
lxc-cmd mkdir -p ${HASSIO_SUPERVISOR_SERVICE}.wants
lxc-cmd ln -s /etc/systemd/system/{hassio-fix-btime.service,hassio-supervisor.service.wants/}

# Start Home Assistant Supervisor
msg "Starting Home Assistant..."
lxc-cmd systemctl start hassio-supervisor.service

# Install 'ha' cli
msg "Installing the 'ha' cli..."
lxc-cmd wget -qLO /usr/bin/ha ${HA_URL_BASE}/ha
lxc-cmd chmod a+x /usr/bin/ha

# Setup 'ha' cli prompt
msg "Configuring 'ha' cli prompt..."
HA_CLI_PATH=/usr/sbin/hassio-cli
lxc-cmd wget -qLO $HA_CLI_PATH https://github.com/home-assistant/operating-system/raw/dev/buildroot-external/rootfs-overlay/usr/sbin/hassos-cli
lxc-cmd sed -i 's,/bin/ash,/bin/bash,g' $HA_CLI_PATH
lxc-cmd sed -i 's,^\(mesg n.*\)$,# \1,' /root/.profile
lxc-cmd chmod a+x $HA_CLI_PATH
lxc-cmd usermod --shell $HA_CLI_PATH root
lxc-cmd bash -c "echo -e '\ncd $HASSIO_DATA_PATH' >> /root/.bashrc"

# Cleanup container
msg "Cleanup..."
lxc-cmd apt-get autoremove >/dev/null
lxc-cmd apt-get autoclean >/dev/null
lxc-cmd rm -rf /var/{cache,log}/* /var/lib/apt/lists/*
### Finish LXC commands ###

# Get network details and show completion message
IP=$(pct exec $CTID ip a s dev eth0 | sed -n '/inet / s/\// /p' | awk '{print $2}')
info "Successfully created Home Assistant LXC to $CTID."
msg "

Home Assistant is reachable by going to the following URLs.

      http://${IP}:8123
      http://${HOSTNAME}.local:8123

"
