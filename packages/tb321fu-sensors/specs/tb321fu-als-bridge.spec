Name:           tb321fu-als-bridge
Version:        0.1.0
Release:        1%{?dist}
Summary:        Lenovo TB321FU ambient light sensor into its IIO device
License:        GPL-3.0-or-later
URL:            https://github.com/enij90/armada-tb321fu
Source0:        tb321fu-als-bridge.c
Source1:        tb321fu-als-bridge.service

BuildRequires:  gcc
BuildRequires:  systemd-rpm-macros
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(libssc)

%description
Reads the TB321FU ambient light sensor from the Qualcomm Sensor Core with
libssc and writes each reading, in lux, to the kernel's tb321fu-als IIO
device, where Steam's adaptive brightness and iio-sensor-proxy read it.

%prep
cp %{SOURCE0} %{SOURCE1} .

%build
%{__cc} %{optflags} %{build_ldflags} -o tb321fu-als-bridge tb321fu-als-bridge.c \
    $(pkg-config --cflags --libs libssc glib-2.0 gobject-2.0) -lm

%install
install -Dpm 0755 tb321fu-als-bridge %{buildroot}%{_libexecdir}/tb321fu-als-bridge
install -Dpm 0644 tb321fu-als-bridge.service %{buildroot}%{_unitdir}/tb321fu-als-bridge.service

%files
%{_libexecdir}/tb321fu-als-bridge
%{_unitdir}/tb321fu-als-bridge.service
