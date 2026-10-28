%global commit b7719402d5d45f64d8ac533ff02698fdd84e1edc

Name:           libssc
Version:        0.4.4
Release:        1.tb321fu.armada%{?dist}
Summary:        Library to access sensors of the Qualcomm Sensor Core (SSC)
License:        GPL-3.0-or-later
URL:            https://github.com/GUF296/libssc
Source0:        %{url}/archive/%{commit}/libssc-%{commit}.tar.gz
# LIBSSC_MAX_SAMPLE_RATE: the IMU's first advertised rate (25 Hz) is too slow for gyro aiming.
Patch0:         libssc-0001-max-sample-rate.patch
Patch1:         libssc-0002-release-the-client-reference-taken-in-open-and-close.patch
Patch2:         libssc-0003-fail-an-open-that-is-never-confirmed.patch
Patch3:         libssc-0004-log-a-failed-disable-before-handing-its-error-to-the-task.patch

BuildRequires:  gcc
BuildRequires:  meson
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(gio-unix-2.0)
BuildRequires:  pkgconfig(qmi-glib)
BuildRequires:  pkgconfig(libprotobuf-c)
BuildRequires:  protobuf-c-compiler
BuildRequires:  protobuf-compiler

%description
libssc talks QMI over QRTR to the Qualcomm Sensor Core and exposes its
accelerometer, gyroscope, light, proximity, magnetometer and compass sensors.
Built from GUF296's TB321FU branch (tb321fu-qcom-sns-20260626.1), on 0.4.3;
upstream 0.4.4 only changes the test mock, so the runtime matches 0.4.4.

%package devel
Summary:        Development files for libssc
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description devel
Headers and pkg-config file for libssc.

%prep
%autosetup -p1 -n libssc-%{commit}

%build
%meson
%meson_build

%install
%meson_install
# GObject introspection is optional upstream; nothing in the image uses it.
rm -rf %{buildroot}%{_libdir}/girepository-1.0 %{buildroot}%{_datadir}/gir-1.0

%files
%license LICENSE
%{_bindir}/ssccli
%{_libdir}/libssc.so.*

%files devel
%{_includedir}/*
%{_libdir}/libssc.so
%{_libdir}/pkgconfig/libssc.pc
