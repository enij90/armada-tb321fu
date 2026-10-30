# Patches

The Android build applies `../mesa/patches/` first, then these. They only go
into the Android driver (`mesa-android` and Lepton's guest), not the host Mesa.

- `patches/0001-tu-gmem-for-shared-ubwc-attachments.patch`
  source: armada
  affects: all GPUs
  notes: black blocks in Lepton when the host scans out Android's UBWC buffers.
