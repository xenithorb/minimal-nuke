#!/bin/bash
# set -x
#
# Usage: ./minimal-nuke.sh [subcommand]
#
# Subcommands:
#			boom:	destroys everything with wreckless abandon
#	to-env <environment>:	installs what is minimally necessary for the listed environment
#			list: 	shows a list of the PROTECTED packages
#		       count:	shows just the end tally of reason file counts from $DNFDB_LOCATION
#			   *:	runs any other function (It's just eval "$1")
#
# Author: Michael Goodwin
#

export LC_ALL=C

# Check for root, normal users have no business with any of this
[[ "$EUID" != "0" ]] && { echo "Need to run with sudo or as root"; exit; }

shopt -s expand_aliases
unalias -a
# Comment this out if you want to type y/n throughout The decision
# making process. However, dnf autoremove will ask for permission still
alias dnf='dnf -y'

DNFDB_LOCATION="/var/lib/dnf/yumdb"

# Packages that WILL BE installed or left alone
PROTECTED=(
	"--exclude=kernel-debug*"
	"kernel"
	"*-firmware"
	#"git"
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
	"vim-minimal"
	"sudo"
)

# Packages that cause errors or that we
# generally want to ignore
NO_INST_PKGS=(
	"ppc64-utils"
	"gpg-pubkey"
)

# Environments we want to end up with
ENVIRONMENTS=(
	"minimal-environment"
#	"standard"
#	"lxde-desktop-environment"
)

# The main DESTRUCTIVE routine
# First get a list of installed environments and all packages, store them as arrays
# Mark all INSTALLED_ENVIRONMENTS as removed (doesn't actually remove anything yet)
# Mark all packages as installed (this sets /var/lib/dnf/yumdb/*/*/reason = user)
# Mark all package removed (this sets /var/lib/dnf/yumdb/*/*/reason = dep)
# Group install the wanted ENVIRONMENTS (dnf will combine them)
setup() {
	readarray -t INSTALLED_ENVIRONMENTS < <( get_installed_envs )
	readarray -t ALL_PACKAGES < <( rpm -qa | grep -vf <( printf '%s\n' "${NO_INST_PKGS[@]}" ) )
	dnf group mark remove "${INSTALLED_ENVIRONMENTS[@]}"
	dnf mark install "${ALL_PACKAGES[@]}" 2>&1 | eat_mark_install_msg
	dnf mark remove "${ALL_PACKAGES[@]}" 2>&1 | eat_mark_install_msg
	dnf group install "${ENVIRONMENTS[@]}"
}

# Install necessary stuff --best is for upgrade scenarios where a dependency needs something upgraded
# because you didn't upgrade yet, and won't install because it only sees the latest packages
install_protected() {
	dnf install --best $(get_keep_list)
	dnf mark install $(get_keep_list) 2>&1 | eat_mark_install_msg
}

# Mark remove/install messages are really unwieldy, so remove them
eat_mark_install_msg() {
	grep -v "marked as user installed.$"
}

# Get a list of the currently installed environments TODO: (Maybe get this also from groups.json?)
get_installed_envs() {
	dnf group list -v hidden \
		| awk 'BEGIN{ FS="[()]" } /Installed env/{ a=1; next } /^[A-Z]/{ a=0 } a{ sub(/^[ ]*/,"") } a{print $2}'
}

# A list of packages that we want to install if missing and keep if already installed
get_keep_list() {
	keep_packages+=( "${PROTECTED[@]}" )
	print_packages() { printf "%s\n" "${keep_packages[@]}"; };
	if [[ "${NO_INST_PKGS[0]}" ]]; then
		print_packages \
			| sort -u | grep -vf <( printf '%s\n' "${NO_INST_PKGS[@]}" )
	else
		# grep -vf <empty_file> will simply act as '*'; which is NOT what we want
		# So, check for something in the array first, hence the IF statement
		print_packages
	fi
}

# This tallies all the different reasons in DNFDB_LOCATION and shows you a package tally at the end
get_reason_count() {
	find "${DNFDB_LOCATION}" -name reason -exec fmt -1 '{}' \+ \
		| sort | uniq -c \
		| awk 'BEGIN{ sum=1 } { sum+=$1; print $0 } END{ print "   ---------\n   ",sum,"TOTAL"}'
}

set_group_reasons() {
	# Gets all bottom entities of a group or environment, recurse as necessary
	get_group_pkgs() {
		strip() {
			awk '/ (Mandatory|Default)/{ a=1; next } /^[ ][A-Z]/{ a=0 } a{ sub(/^[ ]*/,"") } a'
		}
		for i in "$@"; do
			local info
			info="$( dnf group info "$i" )"
			if ( cat <<< "$info" | grep -q "^Environment" ); then
				readarray -t subgroups < <( strip <<< "$info" )
				for j in "${subgroups[@]}"; do
					dnf group info "$j" | strip
				done
			else
				strip <<< "$info"
			fi
		done
	}

	get_group_reason_pkgs() {
		 xargs -a <( get_group_pkgs "${ENVIRONMENTS[@]}" ) rpm -q | sed 's/^/[[:alnum:]]\{40\}-/'
	}

	get_reason_files() {
		find "${DNFDB_LOCATION}" -type f -name "reason"
	}

	readarray -t group_reason_files < <( LC_ALL=C egrep -f <( get_group_reason_pkgs ) < <( get_reason_files ) )
	sed -i 's/.*/group/g' "${group_reason_files[@]}"
}

# The main sub-routine shared between option "boom" and "to-env"
detonate() {
	setup
	set_group_reasons
	install_protected
	# This \ is not a typo, prevents dnf from being aliased with -y
	\dnf autoremove
	get_reason_count
}

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
		command="$1"
		shift
		eval "$command" "$@"
		;;
esac
