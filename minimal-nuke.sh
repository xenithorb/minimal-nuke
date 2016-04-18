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
	"--exclude='kernel-debug*'"
	"kernel"
	#'*-firmware'
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
	#"vim"
	#"vim-minimal"
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
#	"lxde-desktop-environment"
)

# The main DESTRUCTIVE routine
# First we mark all installed environments as remove
# Then we group install ENVIRONMENTS (to actually get packages installed if we need them)
# Then collect a list of packages installed with reason "group" (otherwise lost with dnf mark install)
# Then get a list of all packages and mark them installed (also creates missing yumdb reason files)
# Then mark everything removed (dep)
setup() {
	readarray -t INSTALLED_ENVIRONMENTS < <( get_installed_envs )
	dnf group mark remove "${INSTALLED_ENVIRONMENTS[@]}"
	dnf group install "${ENVIRONMENTS[@]}"
	readarray -t GROUP_REASON_FILES < <( get_yumdb_group_reasons )
	readarray -t all_packages < <( rpm -qa | grep -vf <( printf '%s\n' "${NO_INST_PKGS[@]}" ) )
	dnf mark install "${all_packages[@]}"
	dnf mark remove "${all_packages[@]}"
}

# Install necessary stuff --best is for upgrade scenarios where a dependency needs something upgraded
# because you didn't upgrade yet, and won't install because it only sees the latest packages
# I'm unsure whether dnf install itself will mark install missing or unknown packages or otherwise
# But I know the benavior of mark install, so we're going to mark install all protected packages, too.
install_protected() {
	dnf install --best $(get_keep_list)
	dnf mark install $(get_keep_list)
}

# This gets all the subgroups for an environment TODO: (should maybe be called get_subgroups)
# By design, it gets all subgroups, including Optional groups. For minimal-environment,
# This also means "Guest Agents" and "Standard"
group_info() {
	readarray -t a <<< "$@"
	dnf group info "${a[@]}" | sed -r '/^[ ]{3}/!d;s/^[ ]*//'
}

# Get a list of the currently installed environments TODO: (Maybe get this also from groups.json?)
get_installed_envs() {
	dnf group list -v hidden \
		| sed -r '/^Installed environment/,/^[^ ]/!d;/^[ ]+/!d;s|.*\((.*)\).*|\1|'
}

# A list of packages that we want to install if missing and keep if already installed
get_keep_list() {
	# Commenting this out truly goes minimal all the way
	# Otherwise group_info pulls in Standard and "Guest Agents" as well
	# That's just the way I wanted group_info to work BE CAREFUL
	#readarray -t keep_packages < <( group_info "$( group_info "minimal-environment" )" )
	keep_packages+=( "${PROTECTED[@]}" )
	print_packages() { printf "%s\n" "${keep_packages[@]}"; };
	if [[ $NO_INST_PKGS ]]; then
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

# Prints out all the filenames of packages with reason == "group"
get_yumdb_group_reasons() {
	grep -lR "^group$" "${DNFDB_LOCATION}"
}

# Sets all packages in the array from the above function to == "group"
set_group_reasons() {
	sed -i 's|.*|group|' "${GROUP_REASON_FILES[@]}"
}

# The main sub-routine shared between option "boom" and "to-env"
detonate() {
	setup
	install_protected
	set_group_reasons
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
		eval "$1"
		;;
esac
