#!/usr/bin/env bash

ctid=$1
if [ -z $ctid ]; then
	echo "No container ID provided for env setup!"
	exit 1
fi

LXC_BASE=/var/lib/lxc
CT_BASE="${LXC_BASE}/${ctid}"
LXC_ROOTFS_MOUNT="${CT_BASE}/rootfs/"
