# Armada on the Lenovo Legion Tab Gen 3 (TB321FU) — experimental

This is an **unofficial, experimental** port of [Armada](https://github.com/armada-os/armada)
to the **Lenovo Legion Tab Gen 3 / Legion Y700 (2025), model TB321FU** (Qualcomm Snapdragon 8 Gen 3, SM8650).
It is not supported by the Armada project: please report problems here, not upstream.

> [!WARNING]
> **This guide replaces Android with Armada.** Installing erases all data on the tablet
> and requires an unlocked bootloader. Back up everything first. (Keeping Android
> alongside Armada may be possible, but it is not covered here.)
> You can always go back to stock Android with Lenovo's official rescue tool (LMSA).

## Supported hardware: BOE panel only

The TB321FU ships with two different display panels: **BOE** and **CSOT**. Only **BOE** is
supported for now. On a CSOT tablet the screen stays black.

Check your panel **before doing anything**, from stock Android, with USB debugging enabled
(no root needed):

```bash
adb shell getprop ro.vendor.display.paneltype
```

- `1` → **BOE**: supported.
- anything else, or empty → **not supported** (probably CSOT): stop here.

CSOT support is planned; testers with a CSOT tablet are welcome (open an issue).

## Status

| Feature | Status |
| --- | --- |
| Boot from internal storage | ✅ |
| Display, 1600×2560 BOE, 60/90/120/144/165 Hz, landscape | ✅ |
| Refresh-rate changes without black screen | ✅ |
| Touchscreen | ✅ |
| GPU (Adreno 750, Turnip/Freedreno) | ✅ |
| Hardware video decoding (iris) | ✅ |
| Speakers (2× AW882xx) | ✅ |
| Internal microphones | ⚠️ works, but must be re-enabled after each boot (see known issues) |
| Wi-Fi (WCN7850) | ✅ |
| Bluetooth | ✅ |
| USB-C charging, Lenovo Legion G9 controller (short-side port) | ✅ |
| Suspend (real s2idle) | ✅ about 4% battery overnight |
| Steam Game Mode and KDE Plasma | ✅ |
| Vibration motors (2× AW86937) | ⚠️ driver works, not used by games yet |
| Sensors (accelerometer, gyroscope, light) | ❌ not yet |
| Cameras | ❌ |
| CSOT panel | ❌ |

## Known issues

- **Turn off Steam's performance overlay when you don't need it.** On this tablet
  (2560×1600 at 165 Hz) even the FPS counter makes the compositor redraw every frame on
  the GPU: in the Steam menu the tablet draws about 4.5 W with the overlay on and about
  2.2 W with it off. (Quick Access → Performance → Performance overlay level: Off.)
- **Microphone silent after boot.** A mixer switch (`ADC1 Switch`) stays off after boot.
  Workaround: switch the sound card profile off and back on (e.g. in KDE audio settings).

## Installation

You start from the tablet as it comes from the factory, running Lenovo's Android (ZUI).

What you will need:

- the tablet, charged, with a **BOE** panel (see the check above);
- a PC (Windows, Linux or macOS) with Android's
  [platform-tools](https://developer.android.com/tools/releases/platform-tools) (`adb`, `fastboot`)
  and a USB-C cable;
- a backup of anything you want to keep: the installation erases the tablet.

### 1. Unlock the bootloader

Lenovo tablets are unlocked with a signed unlock file for your serial number:

1. On Android: Settings → About → tap *Build number* 7 times, then in Developer options
   enable **OEM unlocking** and **USB debugging**.
2. Get the unlock file (`sn.img`) for your serial number, for example from
   [lenovobl.neko.ink](https://lenovobl.neko.ink).
3. Flash it and unlock (**this wipes Android**):
   ```bash
   adb reboot bootloader
   fastboot flash unlock sn.img
   fastboot oem unlock-go
   ```

The bootloader stays unlocked even if you later restore stock Android.

### 2. Download and check the images

From the [latest release](https://github.com/enij90/armada-tb321fu/releases) download
`boot.img`, `super.img`, all the `userdata.simg.part*` files and `SHA256SUMS`, into one folder.

Join the userdata parts into `userdata.simg`:

- Windows (Command Prompt, in the download folder):
  ```bat
  copy /b userdata.simg.part1+userdata.simg.part2+userdata.simg.part3+userdata.simg.part4+userdata.simg.part5+userdata.simg.part6 userdata.simg
  ```
- Linux / macOS:
  ```bash
  cat userdata.simg.part* > userdata.simg
  ```

Then check the files against `SHA256SUMS`
(Linux: `sha256sum -c --ignore-missing SHA256SUMS`; Windows: `CertUtil -hashfile userdata.simg SHA256`
and compare by eye, same for `boot.img` and `super.img`).

### 3. Flash

Put the tablet in fastboot mode (`adb reboot bootloader`, or power off and hold
Volume down + Power), connect it to the PC and run:

```bash
fastboot flash boot_a boot.img
fastboot flash super super.img
fastboot -S 700M flash userdata userdata.simg
fastboot reboot
```

`userdata` is sent in about 17 chunks and takes around 5 minutes.

### 4. First boot

Lenovo logo → GRUB → "Preparing Armada" → Wi-Fi and Steam setup. The first boot takes a
little longer. Then you are in Steam's Game Mode.

- Desktop user: `armada`, password `armada`. Change it (`passwd` in a terminal in desktop mode).
- SSH is off by default; you can turn it on in desktop mode → **Armada Tools**.
- System updates come through Steam (Settings → System, software updates). They download in
  the background and apply at the next restart. If a new version does not start, pick the
  GRUB entry marked "(previous)".

### Troubleshooting

- **The tablet stays on the fastboot screen and fastboot stops responding after flashing:**
  choose *START* with the volume keys and press Power, or hold Power for ~15 seconds.
  The partitions are already written.
- **A fastboot command fails halfway:** run `fastboot reboot bootloader`, wait for the tablet
  to come back, then repeat only the failed command.

### Going back to Android

Use Lenovo's official rescue tool, **LMSA** (Lenovo Rescue and Smart Assistant): Rescue →
it downloads and flashes the stock ROM. If the tablet does not boot at all, see
[this XDA unbrick guide](https://xdaforums.com/t/guide-unbrick-lenovo-y700-tablet.4509297/).

## Building

Every push to `main` is built and signed by GitHub Actions and published as
`ghcr.io/enij90/armada-tb321fu:latest`, which installed tablets update from.

Same as upstream Armada (`just build`). The proprietary firmware is not stored in this
repository: the build downloads it from
[firmware-lenovo-tb321fu](https://github.com/enij90/firmware-lenovo-tb321fu)
and checks its SHA-256 (`build_files/tb321fu-firmware.env`). For offline builds, drop
`firmware-lenovo-tb321fu-<version>.tar.gz` into `build_files/`.

Device-specific parts:

- kernel patches `packages/kernel/patches/08xx-*` and DTS `packages/kernel/dts/sm8650-lenovo-tb321fu.dts`;
- device profile `system_files/usr/lib/armada/devices/lenovo-legion-tab.conf`;
- `tb321fu-*` services, UCM and WirePlumber configuration under `system_files/`;
- gamescope patch `0027` (EDID pixel clock above 655.35 MHz, needed for 165 Hz).

## Credits

- **[GUF296](https://github.com/GUF296)**: the first Linux port for this tablet (Kubuntu).
  His kernel and device tree are the starting point of this work. From his tree come:
  - the Novatek NT36523 touch driver;
  - the Parade PS5169 redriver;
  - AudioReach secondary-TDM speaker support;
  - the CSOT panel driver;
  - the UEFI/GRUB boot chain;
  - the AW86937 haptics driver;
  - most of the firmware.
- **[Armada](https://github.com/armada-os/armada)**: the OS this is based on (its original README: [README-armada.md](README-armada.md)).
- **[ROCKNIX](https://github.com/ROCKNIX/distribution)**: SM8650 platform work and inline-rotation support for the display controller.

## License

Same as Armada (GPL-2.0-or-later); kernel patches follow the Linux kernel license.
The firmware in the separate repository is proprietary (see its README).
