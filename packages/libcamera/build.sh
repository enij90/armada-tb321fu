#!/usr/bin/bash
# Runs inside the builder container. See ../build-local.sh for the contract.
set -euxo pipefail

source ./BASE.env

REST="${SRPM#libcamera-}"
LC_VER="${REST%%-*}"
LC_REL="${REST#*-}"
LC_REL="${LC_REL%.fc*}"
DIST=".fc44.armada" # sorts above stock .fc44 so dnf upgrades to the armada build

rm -rf out
mkdir -p out

export HOME=/tmp
dnf -y install rpm-build rpmdevtools koji "dnf-command(builddep)" git-core
rpmdev-setuptree
cat >/etc/rpm/macros.armada <<MACROS
%_buildhost armada-builder
%packager Armada
%vendor Armada
MACROS

cd /tmp
koji download-build --arch=src "${SRPM}"
rpm -i "${SRPM}.src.rpm"
SPEC="$HOME/rpmbuild/SPECS/libcamera.spec"

# Force the stock numeric release so .fc44.armada sorts just above the base
# build, whatever release macro the spec uses.
sed -i "s/^Release:.*/Release:        ${LC_REL}%{?dist}/" "$SPEC"
sed -i "/^%autochangelog/d" "$SPEC"

cp /work/patches/*.patch "$HOME/rpmbuild/SOURCES/"
LAST=$(grep -nE "^(Patch|Source)[0-9]*:" "$SPEC" | tail -1 | cut -d: -f1)
[ -n "$LAST" ] || { echo "ERROR: no Source/Patch line to anchor on"; exit 1; }
sed -i "${LAST}a Patch9001:       0001-libipa-camera_sensor_helper-add-the-lenovo-tb321fu-sensors.patch" "$SPEC"

# The patch lands only if the spec auto-applies it; assert it so a spec change
# cannot silently drop it (a non-matching patch fails rpmbuild itself).
grep -qE "^[[:space:]]*%(autosetup|autopatch)" "$SPEC"     || { echo "ERROR: libcamera.spec does not auto-apply patches; adjust build.sh"; exit 1; }

dnf -y builddep "$SPEC"
# pkgconfig(libdw) is a BuildRequires, but builddep leaves it out here and
# meson then stops at the libdw check.
dnf -y install elfutils-devel
rpmbuild -bb --define "dist ${DIST}" "$SPEC"

# The library, the IPA modules (where the sensor helpers live) and cam(1) for
# testing; qcam, the GStreamer element and the V4L2 compat layer stay out.
for sub in libcamera libcamera-ipa libcamera-tools; do
    cp "$HOME"/rpmbuild/RPMS/*/"${sub}-${LC_VER}-${LC_REL}${DIST}".*.rpm /work/out/
done
