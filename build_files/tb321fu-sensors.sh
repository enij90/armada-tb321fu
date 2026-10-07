#!/usr/bin/bash
# Install the TB321FU sensor stack RPMs (see tb321fu-sensors.env). A local copy
# in build_files/tb321fu-sensors-<version>/ (RPMs + SHA256SUMS) takes precedence.
set -euo pipefail
. /ctx/build_files/tb321fu-sensors.env

dir=/ctx/build_files/tb321fu-sensors-${TB321FU_SNS_VERSION}
if [ ! -d "$dir" ]; then
    dir=$(mktemp -d)
    curl --retry 12 --retry-delay 10 -fsSL -o "$dir/SHA256SUMS" "${TB321FU_SNS_URL}/SHA256SUMS"
fi
echo "${TB321FU_SNS_SUMS_SHA256}  ${dir}/SHA256SUMS" | sha256sum -c -
# Runtime packages only: libssc-devel is a build dependency.
rpms=$(awk '{print $2}' "$dir/SHA256SUMS" | grep -v -- '-devel-')
for r in $rpms; do
    [ -f "$dir/$r" ] || curl --retry 12 --retry-delay 10 -fsSL -o "$dir/$r" "${TB321FU_SNS_URL}/$r"
done
(cd "$dir" && grep -v -- '-devel-' SHA256SUMS | sha256sum -c -)
dnf -y install $(printf "$dir/%s " $rpms)
