#!/bin/bash
#set -x

PROTECTED=(
	"kernel"
	"firmware"
	"grub"
	"shim"
	"efiboot"
	"lvm2"
	"selinux"
	"systemd"
	"^dnf"
)

group_info() {
	readarray -t a <<< "$@"
	dnf group info "${a[@]}" | sed -r '/^[ ]{3}/!d;s/^[ ]*//'
}

get_remove_list() {
	comm -32 <( dnf leaves | xargs rpm -q --qf "%{NAME}\n" | sort -u ) \
		 <( group_info "$( group_info "minimal-environment" )" | sort -u ) \
		 | grep -v -f <( printf "%s\n" "${PROTECTED[@]}" )
}

case "$@" in
	list*) get_remove_list ;;
	*) xargs -pa <( get_remove_list ) dnf remove ;; 
esac