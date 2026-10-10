#!/usr/bin/bash
# Install the TB321FU camera stack: libcamera rebuilt with helpers for the
# tablet's sensors (packages/libcamera), so the software ISP can drive their
# exposure and gain, and PipeWire's libcamera plugin for apps.
set -euo pipefail
dnf -y install /packages/libcamera/*.rpm pipewire-plugin-libcamera
