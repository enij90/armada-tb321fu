#!/usr/bin/bash
# Install the TB321FU sensor stack (packages/tb321fu-sensors): libssc,
# hexagonrpc, iio-sensor-proxy with SSC, tb321fu-imu-bridge.
set -euo pipefail
dnf -y install /packages/tb321fu-sensors/*.rpm
