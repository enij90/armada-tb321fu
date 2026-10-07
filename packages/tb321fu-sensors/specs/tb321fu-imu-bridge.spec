Name:           tb321fu-imu-bridge
Version:        0.1.2
Release:        1%{?dist}
Summary:        Lenovo TB321FU accelerometer and gyroscope as an evdev motion device
License:        GPL-3.0-or-later
URL:            https://github.com/enij90/armada-tb321fu
Source0:        tb321fu-imu-bridge.c
Source1:        tb321fu-imu-bridge.service

BuildRequires:  gcc
BuildRequires:  systemd-rpm-macros
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(libssc)

%description
Reads the TB321FU accelerometer and gyroscope from the Qualcomm Sensor Core
with libssc and reports them on the uinput device "TB321FU IMU" (accelerometer
on ABS_X/Y/Z, gyroscope on ABS_RX/RY/RZ), so InputPlumber can add motion
controls to the Steam Deck controller it presents to Steam.

%prep
cp %{SOURCE0} %{SOURCE1} .

%build
%{__cc} %{optflags} %{build_ldflags} -o tb321fu-imu-bridge tb321fu-imu-bridge.c \
    $(pkg-config --cflags --libs libssc glib-2.0 gobject-2.0) -lm

%install
install -Dpm 0755 tb321fu-imu-bridge %{buildroot}%{_libexecdir}/tb321fu-imu-bridge
install -Dpm 0644 tb321fu-imu-bridge.service %{buildroot}%{_unitdir}/tb321fu-imu-bridge.service

%files
%{_libexecdir}/tb321fu-imu-bridge
%{_unitdir}/tb321fu-imu-bridge.service
