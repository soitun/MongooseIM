#!/usr/bin/env bash
set -e

version=$1
revision=$2
otp_version=$3

arch=$(uname -m)

case "$arch" in
  x86_64)
    package_name_arch="amd64"
    ;;
  aarch64)
    package_name_arch="arm64"
    ;;
  *)
    echo "Unsupported architecture: $arch"
    exit 1
    ;;
esac

rpmbuild -bb \
    --define "version ${version}" \
    --define "release ${revision}" \
    --define "architecture ${arch}" \
    ~/rpmbuild/SPECS/mongooseim.spec

source /etc/os-release
os=$ID
os_version=$VERSION_ID
package_os_file_name=${os}~${os_version}

mv ~/rpmbuild/RPMS/${arch}/mongooseim-${version}-${revision}.${arch}.rpm \
    ~/rpmbuild/mongooseim_${version}_${revision}_otp_${otp_version}~${package_os_file_name}_${package_name_arch}.rpm
