#!/usr/bin/bash
# Build the TB321FU install images from a published image. Runs as root in a
# privileged Fedora container (loop devices, mounts) with the repository at /w;
# the release files land in /w/out.
#   IMAGE             e.g. ghcr.io/enij90/armada-tb321fu:latest
#   TEMPLATE_RELEASE  release whose boot.img and super.img provide the UEFI
#                     loader and GRUB (neither is part of the OS image)
set -euxo pipefail
: "${IMAGE:?}" "${TEMPLATE_RELEASE:?}"

dnf -y install rpm-ostree ostree skopeo btrfs-progs dosfstools android-tools \
    util-linux python3 curl coreutils
df -h /var/tmp /w

repo_url=https://github.com/enij90/armada-tb321fu
work=/var/tmp/relimg
mkdir -p "$work"

# The exact build to package, and its version label.
digest=$(skopeo inspect --format '{{.Digest}}' "docker://${IMAGE}")
version=$(skopeo inspect --format '{{index .Labels "org.opencontainers.image.version"}}' "docker://${IMAGE}")
echo "image ${IMAGE}@${digest} version ${version}"

curl -fsSL -o "$work/boot.img" "${repo_url}/releases/download/${TEMPLATE_RELEASE}/boot.img"
curl -fsSL -o "$work/super.img" "${repo_url}/releases/download/${TEMPLATE_RELEASE}/super.img"

src=$work/src-repo
ostree --repo="$src" init --mode=bare
ostree container image pull "$src" "ostree-unverified-registry:${IMAGE%:*}@${digest}"
commit=$(ostree --repo="$src" rev-parse "$(ostree --repo="$src" refs | grep '^ostree/container/image/' | head -1)")
echo "commit ${commit}"

out=/w/out
rm -rf "$out"
OUT="$out" SRC_REPO="$src" TEMPLATE_SUPER="$work/super.img" BOOT_IMG="$work/boot.img" \
    bash /w/tb321fu/mk-install-images.sh "$commit" "$version"
rm -rf "$src" "$work"
df -h /w

# GitHub release assets are limited to 2 GiB: split userdata (join with
# cat / copy /b, as the README explains). SHA256SUMS also covers the joined file.
cd "$out"
split -b 1900M -d -a 1 --numeric-suffixes=1 userdata.simg userdata.simg.part
sha256sum boot.img super.img userdata.simg.part* > SHA256SUMS.release
sha256sum userdata.simg >> SHA256SUMS.release
rm userdata.simg SHA256SUMS
mv SHA256SUMS.release SHA256SUMS
echo "$version" > VERSION
cat SHA256SUMS
ls -l
