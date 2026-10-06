#!/bin/bash
# Build the TB321FU installation images from an ostree commit. Run as root,
# either on an Armada TB321FU (defaults: the commit is in /sysroot, e.g. the
# staged deployment after `bootc switch`, GRUB and the UEFI loader come from this
# tablet's partitions) or anywhere with the inputs given explicitly:
#   SRC_REPO        ostree repo holding the commit (default /sysroot/ostree/repo)
#   TEMPLATE_SUPER  a super.img to take GRUB from (default: the super partition)
#   BOOT_IMG        the UEFI loader image (default: the boot_a partition)
#
# Output (in $OUT):
#   userdata.img  btrfs (subvol "root") holding one ostree deployment; grows to
#                 the whole partition on first boot (bootc-generic-growpart)
#   super.img     256 MiB FAT: GRUB (EFI/ + boot/grub/ copied from the running
#                 super FAT, i.e. GUF296's template) + kernel, initramfs, DTB, grub.cfg
#   boot.img      the UEFI loader, copied from this tablet's active boot slot
#   SHA256SUMS
set -euo pipefail

COMMIT=${1:?usage: $0 <ostree-commit> [version]}
VERSION=${2:-unknown}
OUT=${OUT:-/var/tmp/tb321fu-install}
SIZE=${SIZE:-16G}
ORIGIN_REF=${ORIGIN_REF:-ostree-image-signed:docker://ghcr.io/enij90/armada-tb321fu:latest}
SRC_REPO=${SRC_REPO:-/sysroot/ostree/repo}
TEMPLATE_SUPER=${TEMPLATE_SUPER:-$(readlink -f /dev/disk/by-partlabel/super)}
BOOT_IMG=${BOOT_IMG:-$(readlink -f /dev/disk/by-partlabel/boot_a)}
OPTS=noatime,compress=zstd:1
# Device kernel arguments the GRUB entry adds to the image's own (kargs.d).
# enforcing=0: SELinux permissive, as on the development install (to revisit).
EXTRA_KARGS=${EXTRA_KARGS:-"efi=novamap console=tty1 fbcon=map:0 enforcing=0"}

log() { echo "==> $*"; }
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
ostree rev-parse --repo="$SRC_REPO" "$COMMIT" >/dev/null

W=$(mktemp -d /var/tmp/mkimg.XXXXXX)
cleanup() {
    set +e
    for m in "$W/sfat-src" "$W/sfat" "$W/target" "$W/top"; do mountpoint -q "$m" && umount "$m"; done
    for l in ${LOOPS:-}; do losetup -d "$l" 2>/dev/null; done
    rm -rf "$W"
}
trap cleanup EXIT
LOOPS=""
mkdir -p "$OUT" "$W"/{top,target,sfat,sfat-src}
rm -f "$OUT"/userdata.img "$OUT"/userdata.simg "$OUT"/super.img "$OUT"/boot.img "$OUT"/SHA256SUMS

log "userdata.img ($SIZE, btrfs)"
UUID=$(cat /proc/sys/kernel/random/uuid)
truncate -s "$SIZE" "$OUT/userdata.img"
mkfs.btrfs -q -f -L root -U "$UUID" "$OUT/userdata.img"
UL=$(losetup -f --show "$OUT/userdata.img"); LOOPS="$LOOPS $UL"
mount -o "$OPTS" "$UL" "$W/top"
btrfs subvolume create "$W/top/root" >/dev/null
umount "$W/top"
mount -o "$OPTS,subvol=root" "$UL" "$W/target"
T=$W/target

log "ostree sysroot"
ostree admin init-fs --modern "$T"
R=$T/ostree/repo
ostree config --repo="$R" set sysroot.bootloader none
ostree config --repo="$R" set sysroot.bootprefix true
ostree config --repo="$R" set sysroot.readonly true
ostree admin os-init --sysroot="$T" default
ostree pull-local --untrusted --repo="$R" "$SRC_REPO" "$COMMIT"
ostree fsck --repo="$R" >/dev/null

log "kernel arguments from the image (usr/lib/bootc/kargs.d, as armada-installer)"
ostree checkout --repo="$R" --subpath=/usr/lib/bootc/kargs.d "$COMMIT" "$W/kargs.d"
KARGS=()
while IFS= read -r a; do KARGS+=("--karg=$a"); done < <(python3 - "$W/kargs.d" <<'PY'
import pathlib, platform, sys, tomllib
for p in sorted(pathlib.Path(sys.argv[1]).glob("*.toml")):
    d = tomllib.loads(p.read_text())
    if "match-architectures" in d and platform.machine() not in d["match-architectures"]:
        continue
    for v in d.get("kargs", []):
        if not v.startswith(("root=", "boot=", "rootflags=", "ostree=")):
            print(v)
PY
)

log "deploy $COMMIT"
printf '[origin]\ncontainer-image-reference=%s\n' "$ORIGIN_REF" > "$W/origin"
ostree admin deploy --no-merge --origin-file="$W/origin" --sysroot="$T" --os=default \
    --karg="root=UUID=$UUID" --karg="rootflags=subvol=root,$OPTS" --karg=rw --karg=rootwait \
    "${KARGS[@]}" "$COMMIT"

log "seed /var from the image (as armada-installer)"
ostree checkout --repo="$R" --subpath=/var "$COMMIT" "$W/var-seed"
cp -a "$W/var-seed/." "$T/ostree/deploy/default/var/"

ENTRY=$(ls "$T"/boot/loader/entries/*.conf | head -1)
OPTIONS=$(sed -n 's/^options //p' "$ENTRY")
LINUX=$(sed -n 's/^linux //p' "$ENTRY"); INITRD=$(sed -n 's/^initrd //p' "$ENTRY")
DEP=$(ls -d "$T"/ostree/deploy/default/deploy/*.0)
DTB=$(ls "$DEP"/usr/lib/modules/*/dtb/qcom/sm8650-lenovo-tb321fu.dtb | head -1)
log "entry: linux=$LINUX initrd=$INITRD"
log "options: $OPTIONS"

log "super.img (256 MiB FAT, GRUB template from $TEMPLATE_SUPER)"
SL=$(losetup -f --show -r --sector-size 512 "$TEMPLATE_SUPER"); LOOPS="$LOOPS $SL"
mount -o ro "$SL" "$W/sfat-src"
truncate -s 256M "$OUT/super.img"
mkfs.vfat -F 32 -n Y700BOOT "$OUT/super.img" >/dev/null
FL=$(losetup -f --show "$OUT/super.img"); LOOPS="$LOOPS $FL"
mount "$FL" "$W/sfat"
S=$W/sfat
mkdir -p "$S/EFI/BOOT" "$S/boot/grub" "$S/dtb"
cp -r "$W"/sfat-src/EFI/BOOT/. "$S/EFI/BOOT/"
cp -r "$W/sfat-src/boot/grub/arm64-efi" "$S/boot/grub/"
[ -d "$W/sfat-src/boot/grub/fonts" ] && cp -r "$W/sfat-src/boot/grub/fonts" "$S/boot/grub/"
cp "$T$LINUX" "$S/Image"
cp "$T$INITRD" "$S/initramfs.img"
cp "$DTB" "$S/dtb/sm8650-lenovo-tb321fu.dtb"
cat > "$S/boot/grub/grub.cfg" <<EOF
set timeout=3
set default=0
set gfxpayload=keep

# GRUB sets \$root to this FAT; no "search" (it would probe the btrfs userdata).

menuentry "Armada $VERSION" {
    devicetree /dtb/sm8650-lenovo-tb321fu.dtb
    linux /Image $OPTIONS $EXTRA_KARGS
    initrd /initramfs.img
}

menuentry "Power off" {
    halt
}
EOF
# GRUB reads /boot/grub/grub.cfg (its prefix), which tb321fu-grub-sync rewrites on
# every update; the copy next to the EFI binary only points there.
echo 'configfile /boot/grub/grub.cfg' > "$S/EFI/BOOT/grub.cfg"
sync
umount "$W/sfat-src" "$S"
fsck.fat -n "$OUT/super.img" | tail -1

log "boot.img (UEFI loader from $BOOT_IMG)"
dd if="$BOOT_IMG" of="$OUT/boot.img" bs=1M status=none

umount "$T"
btrfs check --readonly "$OUT/userdata.img" >/dev/null 2>&1 && log "btrfs check ok"
# Windows fastboot dies (bad_alloc) on a 16 GiB raw image: ship it Android-sparse.
img2simg "$OUT/userdata.img" "$OUT/userdata.simg" && rm "$OUT/userdata.img"
(cd "$OUT" && sha256sum userdata.simg super.img boot.img > SHA256SUMS && cat SHA256SUMS)
log "done: $OUT (root UUID $UUID)"
