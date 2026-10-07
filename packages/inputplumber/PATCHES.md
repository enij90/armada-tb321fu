# Patches

Patches applied on top of BASE.env. Each entry's `source` is an upstream URL pinned
to a commit, or `armada` if it's original; a URL source with no `notes` is verbatim.
`notes` mean the file was modified.

- `patches/0001-fix-gamepad-share-raw-input.patch`
  source: armada
- `patches/0002-fix-force-feedback-reset-effects-when-replacing-targets.patch`
  source: armada
- `patches/0003-feat-Hardware-Support-Add-AYN-Thor-Lite.patch`
  source: https://github.com/ShadowBlip/InputPlumber/pull/746
  notes: AYN Thor Lite support
- `patches/0005-feat-Hardware-Support-accept-the-TB321FU-IMU-bridge.patch`
  source: armada
  notes: Whitelists the virtual device "TB321FU IMU" (tb321fu-imu-bridge: the Lenovo TB321FU's
  accelerometer and gyroscope from the Qualcomm sensor core, which has no IIO device).
- `patches/0006-fix-evdev-keep-the-Legion-G9-Legion-button-held-through-chords.patch`
  source: armada
  notes: The Legion G9 (3537:1134) hides BTN_MODE while another button is held with it;
  keep it held through the chord and delay its release by 200 ms.
