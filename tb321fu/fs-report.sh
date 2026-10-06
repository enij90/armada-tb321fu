#!/usr/bin/bash
# Size breakdown of an install image's root subvolume, to compare builds.
# Usage: fs-report.sh <label> <mountpoint of subvol=root>
set -uo pipefail
label=$1 m=$2
echo "===== fs-report: ${label}"
btrfs filesystem df "$m" | sed 's/^/  /'
command -v compsize >/dev/null && compsize -x "$m" | sed 's/^/  /'
echo "  top level:"
du -xs --apparent-size -BM "$m"/* 2>/dev/null | sed 's/^/    /'
echo "  ostree repo objects: $(find "$m/ostree/repo/objects" -type f | wc -l) files, $(du -xs -BM "$m/ostree/repo" | cut -f1)"
dep=$(ls -d "$m"/ostree/deploy/default/deploy/*.0 | head -1)
echo "  deployment $(basename "$dep"): $(du -xs --apparent-size -BM "$dep" | cut -f1) apparent"
echo "  /var: $(du -xs --apparent-size -BM "$m/ostree/deploy/default/var" | cut -f1) apparent"
labeled=$(find "$dep/usr/bin" -maxdepth 1 -type f | head -200 | xargs getfattr --absolute-names -n security.selinux 2>/dev/null | grep -c '^security.selinux=')
echo "  SELinux labels on the first 200 files of usr/bin: ${labeled}"
echo "  boot entries:"; ls "$m"/boot/loader/entries/ 2>/dev/null | sed 's/^/    /'
