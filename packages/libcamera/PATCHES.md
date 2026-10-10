# Patches

Patches applied on top of BASE.env. Each entry's `source` is an upstream URL pinned
to a commit, or `armada` if it's original; a URL source with no `notes` is verbatim.
`notes` mean the file was modified.

- `patches/0001-libipa-camera_sensor_helper-add-the-lenovo-tb321fu-sensors.patch`
  source: armada
  upstream: local
  notes: Gain models follow GUF296's TB321FU sensor drivers (linear, 1024 = 1x) and the upstream ov13b10 driver (linear, 0x80 = 1x).
