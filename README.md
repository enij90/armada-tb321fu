# Armada on the Lenovo Legion Tab Gen 3 (TB321FU) — experimental

This is an **unofficial, experimental** port of [Armada](https://github.com/armada-os/armada)
to the **Lenovo Legion Tab Gen 3 / Legion Y700 (2025), model TB321FU** (Qualcomm Snapdragon 8 Gen 3, SM8650).
It is not supported by the Armada project: please report problems here, not upstream.

> [!WARNING]
> **This guide replaces Android with Armada.** Installing erases all data on the tablet
> and requires an unlocked bootloader. Back up everything first. (Keeping Android
> alongside Armada may be possible, but it is not covered here.)
> You can always go back to stock Android with Lenovo's official rescue tool (LMSA).

## Supported hardware: BOE panel, CSOT untested

The TB321FU ships with two different display panels: **BOE** and **CSOT**. **BOE** is
supported. **CSOT** has its own boot entry but nobody has tried it yet (see
[CSOT panel](#csot-panel-untested)).

Check your panel **before doing anything**, from stock Android, with USB debugging enabled
(no root needed):

```bash
adb shell getprop ro.vendor.display.paneltype
```

- `1` → **BOE**: supported.
- anything else, or empty → probably **CSOT**: untested. If you want to try it, read
  [CSOT panel](#csot-panel-untested) first, and keep the stock firmware at hand to go back.

## Status

| Feature | Status |
| --- | --- |
| Display, 1600×2560 BOE, 60/90/120/144/165 Hz, landscape | ✅ |
| Variable refresh rate (VRR), 40–165 Hz | ✅ |
| Touchscreen | ✅ |
| GPU (Adreno 750, Turnip/Freedreno) | ✅ |
| Hardware video decoding (iris), also in Steam Remote Play | ✅ |
| Speakers (2× AW882xx) | ✅ |
| Internal microphones | ✅ |
| Wi-Fi (WCN7850) | ✅ |
| Bluetooth | 🚧 work in progress (see known issues) |
| USB-C charging, charges to 100% | ✅ |
| USB-C display output (DisplayPort Alt Mode), video | ✅ |
| USB-C display output, audio | ✅ (see known issues) |
| Lenovo Legion G9 controller (short-side port), see below | ✅ |
| Headphones on the G9's jack | ✅ |
| Vibration motors (2× AW86937), game rumble | ✅ |
| Sensors (accelerometer, gyroscope, light); gyro available to Steam Input | ✅ |
| Adaptive brightness (light sensor) | ✅ |
| Cameras: 3 via libcamera (image quality not tuned yet) | ✅ |
| CSOT panel | 🧪 untested, see below |

### Legion G9 controller

- Shows up in Steam as a Steam Deck controller, with gyro (from the tablet).
- The **Legion button** is Steam's button, including its shortcuts (hold Legion and press
  another button). Holding it alone for a few seconds turns the controller off (firmware).
- The volume shortcuts of the controller's firmware are off: use Steam's.
- The **light strips** can be set from Armada Control.
- The four **back buttons** cannot be used as separate buttons: the controller firmware
  reports each one as one of the other buttons. To change it on the controller, press
  **M** together with the back button, then the button it should send (Lenovo's Android
  app can do it too). The M button is handled by the firmware only and cannot be mapped.

### CSOT panel (untested)

Some units have a CSOT panel instead of the BOE one (on Android,
`getprop ro.vendor.display.paneltype` gives 1 on BOE units). With the default
entry a CSOT unit shows only a black screen after GRUB. To try it:

1. In the GRUB menu (3 seconds after the Lenovo logo), pick the entry ending in
   **(CSOT panel)**.
2. If Game Mode comes up and touch works, make it the default: open a terminal in
   Desktop Mode (or connect over SSH) and run `sudo tb321fu-panel csot`.
   `sudo tb321fu-panel boe` goes back.

Please report the result in an issue, whether it works or not.

### Battery

- The tablet charges to 100%. Android's battery care limit (70–80%), which the battery
  firmware keeps, is cleared at every boot.
- At 3% it powers off instead of suspending, also while asleep: a flat battery could leave
  it unable to start, even on the charger, until a forced reset.

## Recent changes

- **Standby:** the tablet now sleeps much deeper: overnight it uses about half the battery
  it did. The sensors stop while it sleeps, Wi-Fi powers off and on again cleanly, and an
  app that leaves sound open no longer keeps the audio processor awake (part of the work
  comes from Armada's SM8750 sleep change).
- **Bluetooth:** the radio now loads this tablet's own settings from its Android partition.
  Pair devices again after the update.
- **Sound over USB-C:** a TV or monitor on USB-C now plays the sound too.
- **Volume:** the speaker volume steps are even across the whole slider.
- **Charging:** Steam shows the tablet as charging, with the time to full, instead of
  discharging.
- **Cameras:** in low light the main camera slows down to 30 fps to take in more light,
  instead of staying at 60 fps with a dark, noisy picture.
- **Steam Remote Play:** colours match the host (the picture was washed out and bluish).
- **Legion G9:** the controller keeps USB when a charger or hub is plugged into the other
  port, in whatever order.
- **External display:** a TV or monitor on USB-C now shows Game Mode, and becomes the main
  screen while it is connected. Sound over USB-C is not there yet.
- **Brightness:** the whole slider changes the light, not only its upper half, and the
  lowest step is darker, for use in the dark.
- **Clock:** the time is right from boot, also without network. Before, every boot started
  on 14 September until the network time arrived, and files created in the meantime were
  later removed as old: this made the performance overlay use CPU even when hidden and
  Decky disappear after a Steam restart.
- **Decky Loader** runs natively instead of through the x86-64 emulator (from Armada's
  pending change by ouroboros420).
- **Logs:** a message repeated five times a second by the audio DSP is gone, so the system
  log keeps its history (fix by GUF296).
- **Legion G9:** the light strips are restored at boot, after sleep and after the controller
  reconnects.
- **Variable refresh rate (VRR):** the display follows the game's frame rate between 40 and
  165 Hz. Turn it on in the Quick Access menu. At rest the display drops to
  40 Hz, which saves about half a watt. Two fixes to Armada's VRR patches were needed for
  this tablet's display, which is driven by two DSI links with compression.
- **Adaptive brightness:** the light sensor now drives Steam's adaptive brightness
  (Settings → Display).
- **Upstream Armada:** merged the latest changes, among them the Decky Quick Access
  alignment and "Switch to Desktop" on the first boot.
- **Display:** the seam between the two halves of a rotated image is fixed: no more doubled
  line. The display controller rotates the image by default instead of the GPU shader, which
  uses less power in games.
- **Cameras:** the three cameras work through libcamera, so apps that use PipeWire or
  libcamera can see them. Depending on the unit, the main rear camera uses one of two
  sensors, OmniVision OV13B10 or GalaxyCore GC13A0, and the tablet uses whichever one it
  finds. Only the OV13B10 has been tested: the GC13A0 driver (from GUF296) is included but
  untested, reports from units with that sensor are welcome.
- **Steam Remote Play** (client) decodes video in hardware (iris) and shows the right colours.

## Known issues

- Sometimes, after GRUB, the tablet restarts once or twice before booting. It then
  starts normally.
- Camera image quality is not tuned yet: the second rear camera is a macro camera and is
  blurry at a distance, and the OV13B10 sensor shows line corruption in RAW at 60 and 120 fps.
- Sound over USB-C: sometimes the TV stays silent after plugging in. Unplug and plug it
  in again.
- Bluetooth is still work in progress: Steam's device list empties after a while (turn
  Bluetooth off and on to search again), and phone calls routed to the tablet make the
  radio restart.

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
  copy /b userdata.simg.part* userdata.simg
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
- gamescope patch `0030` (EDID pixel clock above 655.35 MHz, needed for 165 Hz);
- Steam Remote Play hardware decoding shim, `packages/steam-v4l2-shim` (loaded only by Steam's `streaming_client`);
- InputPlumber profile and patch for the Legion G9, `armada-rgb` backend for its light strips;
- sensors from the Qualcomm Sensor Core (libssc), `packages/tb321fu-sensors`: motion sensors
  for InputPlumber and the light sensor for Steam (kernel patch `0827`).

## Credits

- **[GUF296](https://github.com/GUF296)**: the first Linux port for this tablet (Kubuntu).
  His kernel and device tree are the starting point of this work. From his tree come:
  - the Novatek NT36523 touch driver;
  - the Parade PS5169 redriver;
  - AudioReach secondary-TDM speaker support;
  - the CSOT panel driver;
  - the UEFI/GRUB boot chain;
  - the AW86937 haptics driver;
  - the camera drivers;
  - most of the firmware.
- **[Armada](https://github.com/armada-os/armada)**: the OS this is based on (its original README: [README-armada.md](README-armada.md)).
- **[ROCKNIX](https://github.com/ROCKNIX/distribution)**: SM8650 platform work and inline-rotation support for the display controller.

## License

Same as Armada (GPL-2.0-or-later); kernel patches follow the Linux kernel license.
The firmware in the separate repository is proprietary (see its README).
