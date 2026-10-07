%global commit 4054d61222b473c1b172a04faf0677845201ec7f

Name:           iio-sensor-proxy
# Epoch: replaces Fedora's build (no SSC backend) in the TB321FU image.
Epoch:          1
Version:        3.9
Release:        1.tb321fu%{?dist}
Summary:        IIO sensors to D-Bus proxy, with the Qualcomm SSC backend
License:        GPL-3.0-or-later
URL:            https://github.com/GUF296/iio-sensor-proxy
Source0:        %{url}/archive/%{commit}/iio-sensor-proxy-%{commit}.tar.gz

BuildRequires:  gcc
BuildRequires:  meson
BuildRequires:  systemd-rpm-macros
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(gudev-1.0)
BuildRequires:  pkgconfig(polkit-gobject-1)
BuildRequires:  pkgconfig(systemd)
BuildRequires:  pkgconfig(udev)
BuildRequires:  pkgconfig(libssc)

%description
iio-sensor-proxy exposes accelerometer orientation, ambient light, proximity
and compass readings on D-Bus (net.hadess.SensorProxy). This is GUF296's
TB321FU branch (tb321fu-qcom-sns-20260626.1) with the Qualcomm SSC backend,
built against libssc.

%prep
%autosetup -n iio-sensor-proxy-%{commit}

%build
%meson -Dssc-support=enabled -Dtests=false -Dgtk-tests=false -Dgtk_doc=false
%meson_build

%install
%meson_install

%post
%systemd_post iio-sensor-proxy.service

%preun
%systemd_preun iio-sensor-proxy.service

%postun
%systemd_postun_with_restart iio-sensor-proxy.service

%files
%license COPYING
%{_bindir}/monitor-sensor
%{_libexecdir}/iio-sensor-proxy
%{_unitdir}/iio-sensor-proxy.service
%{_udevrulesdir}/*-iio-sensor-proxy.rules
%{_datadir}/dbus-1/system.d/net.hadess.SensorProxy.conf
%{_datadir}/polkit-1/actions/net.hadess.SensorProxy.policy
