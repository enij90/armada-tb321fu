%global commit 86d7a139ef35bb2e62ea13bd7b166a1ec08a4b97

Name:           hexagonrpc
Version:        0.4.0
Release:        1.tb321fu%{?dist}
Summary:        FastRPC daemon serving files to Qualcomm Hexagon DSPs
License:        GPL-3.0-or-later
URL:            https://github.com/GUF296/hexagonrpc
Source0:        %{url}/archive/%{commit}/hexagonrpc-%{commit}.tar.gz

BuildRequires:  gcc
BuildRequires:  meson

%description
hexagonrpcd answers the remote file system calls of a Qualcomm DSP over
FastRPC. On the Lenovo TB321FU the ADSP sensor PD reads its sensor registry
through it. GUF296's TB321FU branch (tb321fu-qcom-sns-20260626.1), with the
persistent registry kept under /var/lib/qcom-sns.

%prep
%autosetup -n hexagonrpc-%{commit}
# Same relocation as GUF296's qcom-sns packaging (build-y700-sensor-debs.sh).
sed -i \
    -e 's#Y700_REGISTRY_ROOT#QCOM_SNS_REGISTRY_ROOT#g' \
    -e 's#/var/lib/y700-sns/persist/sensors/registry#/var/lib/qcom-sns/persist/sensors/registry#g' \
    hexagonrpcd/apps_std.c
grep -q 'QCOM_SNS_REGISTRY_ROOT "/var/lib/qcom-sns/persist/sensors/registry"' hexagonrpcd/apps_std.c

%build
%meson
%meson_build

%install
%meson_install
# The TB321FU uses its own qcom-sns-init unit; drop the generic upstream ones
# and the development files nothing links against.
rm -f %{buildroot}%{_libdir}/systemd/system/hexagonrpcd-*.service
rm -f %{buildroot}%{_prefix}/lib/systemd/system/hexagonrpcd-*.service
rm -f %{buildroot}%{_libdir}/libhexagonrpc.so

%files
%license COPYING
%{_bindir}/hexagonrpcd
%{_libexecdir}/hexagonrpc/
%{_libdir}/libhexagonrpc.so.*
%{_mandir}/man1/hexagonrpcd.1*
