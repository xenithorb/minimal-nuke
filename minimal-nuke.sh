#!/bin/bash
#set -x

PROTECTED=(
	"kernel*"
	'*-firmware'
	"grub*"
	"shim"
	"efibootmgr"
	"lvm2*"
	"selinux*"
	"systemd*"
	"dnf*"
	"iproute*"
	"vim*"
	"vi*"
	"sudo"
)

setup() {
	readarray -t all_packages < <(rpm -qa)
	sudo dnf mark install "${all_packages[@]}"
	sudo find /var/lib/dnf/yumdb -type f -name "reason" -exec sed -i 's/user/dep/g' '{}' \+
}

group_info() {
	readarray -t a <<< "$@"
	dnf group info "${a[@]}" | sed -r '/^[ ]{3}/!d;s/^[ ]*//'
}

#get_remove_list() {
#	comm -32 <( dnf leaves | xargs rpm -q --qf "%{NAME}\n" | sort -u ) \
#		 <( group_info "$( group_info "minimal-environment" )" | sort -u ) \
#		 | grep -v -f <( printf "%s\n" "${PROTECTED[@]}" )
#}

get_keep_list() {
	readarray -t keep_packages < <( group_info "$( group_info "minimal-environment" )" )
	keep_packages+=( "${PROTECTED[@]}" )
	printf "%s\n" "${keep_packages[@]}" 
}


case "$@" in
	list*) get_keep_list ;;
	*)
		setup
		sudo dnf install $(get_keep_list)
		sudo dnf mark install $(get_keep_list)
		sudo dnf autoremove 
	;;

#	*) xargs -a <( get_remove_list ) dnf remove ;; 
esac