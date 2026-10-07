#!/usr/bin/bash
# Runs inside the builder container. See ../build-local.sh for the contract.
# Lenovo TB321FU sensor stack: libssc, hexagonrpc, iio-sensor-proxy with the
# SSC backend (GUF296's forks) and tb321fu-imu-bridge.
set -euxo pipefail

rm -rf out
mkdir -p out

export HOME=/tmp
dnf -y install rpm-build rpmdevtools spectool "dnf-command(builddep)"
rpmdev-setuptree
cat >/etc/rpm/macros.armada <<EOF
%_buildhost armada-builder
%packager Armada
%vendor Armada
EOF
top=$(rpm --eval '%{_topdir}')
cp /work/specs/*.spec "$top/SPECS/"
cp /work/specs/*.patch /work/bridge/* "$top/SOURCES/"

build() {
    local spec="$top/SPECS/$1.spec"
    spectool -g -R "$spec"
    dnf -y builddep "$spec"
    rpmbuild -bb --define 'debug_package %{nil}' "$spec"
}

# libssc first: iio-sensor-proxy and the bridge build against it.
build libssc
dnf -y install "$top"/RPMS/*/libssc-[0-9]*.rpm "$top"/RPMS/*/libssc-devel-*.rpm
build hexagonrpc
build iio-sensor-proxy
build tb321fu-imu-bridge

# Runtime packages only: libssc-devel is a build dependency.
find "$top/RPMS" -name '*.rpm' ! -name '*-devel-*' -exec cp {} /work/out/ \;
ls -l /work/out
