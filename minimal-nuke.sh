#!/bin/bash
#set -x

[[ "$EUID" != "0" ]] && { echo "Need to run with sudo or as root"; exit; }

shopt -s expand_aliases
unalias -a
alias dnf='dnf -y'

DNFDB_LOCATION="/var/lib/dnf/yumdb"
PROTECTED=(
	"--exclude='kernel-debug*'"
	"kernel"
	'*-firmware'
	"git"
	"grub2"
	"grub2-efi"
	"shim"
	"cryptsetup"
	"efibootmgr"
	"lvm2"
	"selinux-policy"
	"selinux-policy-targeted"
	"bash"
	"systemd"
	"dnf"
	"iproute"
	"coreutils"
	"dhcp-client"
	"vim"
	"vim-minimal"
	"sudo"
)

NO_INST_PKGS=(
	"ppc64-utils"
	"gpg-pubkey"
)

ENVIRONMENTS=(
	"minimal-environment"
#	"lxde-desktop-environment"
)

setup() {
	rm -rf "${DNFDB_LOCATION:?ERROR: Unset variable}"/*
	dnf group mark remove "${INSTALLED_ENVIRONMENTS[@]}"
	dnf group install "${ENVIRONMENTS[@]}"
	readarray -t GROUP_REASON_FILES < <( get_yumdb_group_reasons )
	readarray -t all_packages < <( rpm -qa | grep -vf <( printf '%s\n' "${NO_INST_PKGS[@]}" ) )
	dnf mark install "${all_packages[@]}"
	find "${DNFDB_LOCATION}" -type f -name "reason" -exec sed -i 's|user|dep|' '{}' \+
}

install_protected() {
	dnf install --best $(get_keep_list)
	dnf mark install $(get_keep_list)
}

group_info() {
	readarray -t a <<< "$@"
	dnf group info "${a[@]}" | sed -r '/^[ ]{3}/!d;s/^[ ]*//'
}

get_installed_envs() {
	dnf group list -v hidden \
		| sed -r '/^Installed environment/,/^[^ ]/!d;/^[ ]+/!d;s|.*\((.*)\).*|\1|'
}

get_keep_list() {
	readarray -t keep_packages < <( group_info "$( group_info "minimal-environment" )" )
	keep_packages+=( "${PROTECTED[@]}" )
	print_packages() { printf "%s\n" "${keep_packages[@]}"; };
	if [[ $NO_INST_PKGS ]]; then
		print_packages \
			| sort -u | grep -vf <( printf '%s\n' "${NO_INST_PKGS[@]}" )
	else
		print_packages
	fi
}

get_reason_count() {
	find "${DNFDB_LOCATION}" -name reason -exec fmt -1 '{}' \+ \
		| sort | uniq -c \
		| awk 'BEGIN{ sum=1 } { sum+=$1; print $0 } END{ print "   ---------\n   ",sum,"TOTAL"}'
}

get_yumdb_group_reasons() {
	grep -lR "^group$" "${DNFDB_LOCATION}"
}

set_group_reasons() {
	sed -i 's|.*|group|' "${GROUP_REASON_FILES[@]}"
}

detonate() {
	setup
	install_protected
	set_group_reasons
	\dnf autoremove
	get_reason_count
}

readarray -t INSTALLED_ENVIRONMENTS < <( get_installed_envs )

case "$@" in
	boom*)
		detonate
		;;
	to-env*)
		shift
		ENVIRONMENTS+=( "$@" )
		detonate
		;;
	list*)
		get_keep_list
		;;
	count*)
		get_reason_count
		;;
	*)
		eval "$1"
		;;
esac
