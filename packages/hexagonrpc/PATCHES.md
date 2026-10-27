# Patches

Patches applied on top of Terra's hexagonrpc spec at TERRA.env. Each entry's
`source` is an upstream URL pinned to a commit, or `armada` if it is original;
a URL source with no `notes` is verbatim. `notes` mean the file was modified.

- `patches/0006-hexagonrpcd-add-sns-registry-reverse-interface.patch`
  source: https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550/blob/3548c401e6d2193a8a9ba7ef08add7074ea53f9e/external-and-mods/kernel/vendor/qcom-gyro/src/hexagonrpc/0002-hexagonrpcd-add-sns-registry-reverse-interface.patch
  notes: Unmodified. Written by suckbluefrog for their Batocera ARM builds (github.com/suckbluefrog/Batocera-Custom-Arm-Builds, since deleted); the source above is the earliest surviving copy.
- `patches/0007-hexagonrpcd-add-writable-hexagonfs.patch`
  source: https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550/blob/3548c401e6d2193a8a9ba7ef08add7074ea53f9e/external-and-mods/kernel/vendor/qcom-gyro/src/hexagonrpc/0005-hexagonrpcd-add-writable-hexagonfs.patch
- `patches/0008-hexagonrpcd-support-writable-sensor-registry.patch`
  source: https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550/blob/3548c401e6d2193a8a9ba7ef08add7074ea53f9e/external-and-mods/kernel/vendor/qcom-gyro/src/hexagonrpc/0006-hexagonrpcd-support-writable-sensor-registry.patch
- `patches/0009-hexagonrpcd-support-large-and-extended-callbacks.patch`
  source: https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550/blob/3548c401e6d2193a8a9ba7ef08add7074ea53f9e/external-and-mods/kernel/vendor/qcom-gyro/src/hexagonrpc/0007-hexagonrpcd-support-large-and-extended-callbacks.patch
