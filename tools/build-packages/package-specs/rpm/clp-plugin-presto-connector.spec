Name:           clp-plugin-presto-connector
Version:        %{pkg_version}
Release:        %{pkg_release}
Summary:        CLP plugins for Presto coordinator (Java) and Velox worker (C++)
License:        Apache-2.0
URL:            https://github.com/y-scope/clp-plugin-presto-connector
Packager:       YScope Inc. <support@yscope.com>

# Target arch is set via `rpmbuild --target` from entrypoint.sh (x86_64 for
# amd64, aarch64 for arm64); no BuildArch: directive needed here.
#
# Loose deps to match the .deb's Depends:; don't let rpm auto-scan the JAR/.so.
AutoReqProv:    no
Requires:       glibc >= 2.28
Requires:       libstdc++

%description
Bundles both halves of the CLP Presto integration in a single package:

  * Java JAR - Presto coordinator connector that exposes CLP datasets as
    Presto tables.
  * C++ .so  - Velox worker plugin that pushes CLP-format scans down into
    the native execution engine.

Compiled on manylinux_2_28 (glibc >= 2.28); compatible with RHEL 8+,
AlmaLinux 8+, Rocky 8+, Fedora 29+, and other glibc-based RPM distros.
Non-system native runtime libraries are bundled beside the Velox plugin and
loaded through relative RUNPATHs, so the package does not depend on distro
OpenSSL/libcurl versions.

%install
cp -a %{payload_dir}/. %{buildroot}/

# Explicitly own the leaf install dirs so rpm tracks and removes them on
# uninstall. The top-level /opt/clp-plugin-presto-connector/ is created
# implicitly when rpm processes the first child %dir entry.
%files
%dir %{presto_jar_dir}
%{presto_jar_dir}/clp-plugin-presto-connector.jar
%dir %{velox_so_dir}
%{velox_so_dir}/libclp-plugin-velox-connector.so
%dir %{velox_so_dir}/lib
%{velox_so_dir}/lib/*
