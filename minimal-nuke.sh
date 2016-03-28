#!/bin/bash
xargs -pa <(
  comm -32 <(
    sort -u <(
      dnf leaves \
        | xargs rpm -q --qf "%{NAME}\n"
      )
    ) <( 
    sort -u <(
      dnf group info $(dnf group info minimal-environment | sed '/^   /!d') \
        | sed '/^   /!d;s/^[ ]*//'
    )
  ) \
  | sed -r '/(kernel|firmware|grub|shim|efiboot|lvm2|selinux|systemd|^dnf)/d' 
  ) dnf remove