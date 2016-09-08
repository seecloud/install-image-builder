#!/usr/bin/env bash

readonly PRESEED DISTRO_DIR="$(mktemp -d)" DISTRO_CN="$(lsb_release -cs)"

inject_preseed() {
  cp -f "${PRESEED}" "${DISTRO_DIR}/preseed/"
}

create_repo() {
  local -r packages='docker-engine ansible' tmp_dir="$(mktemp -d)"

  apt-cdrom -m -d=/media/cdrom add

  # Add Docker's APT repository
  local -r repo='deb http://apt.dockerproject.org/repo ubuntu-trusty main'
  echo "${repo}" > /etc/apt/sources.list.d/docker.list
  apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 \
    --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

  apt-get clean
  apt-get update
  apt-get -qq --print-uris install ${packages} | \
    grep -v 'cdrom:\[' | \
    cut -d ' ' -f 1 | \
    sed -r "s/(^'|'$)//g" > /tmp/packages.txt
  wget -q -P "${tmp_dir}" -i /tmp/packages.txt

  apt-get -y install reprepro fakeroot dpkg-dev squashfs-tools

  mkdir "${HOME}/.gnupg"
  cp -rf "${HOME}"/config/gnupg/* "${HOME}/.gnupg"
  cp -rf "${HOME}"/config/reprepro/* "${DISTRO_DIR}"
  rm -rf "${DISTRO_DIR}/dists/${DISTRO_CN}"

  for pkg in deb udeb; do
    find "${DISTRO_DIR}/pool" -type f -name "*\.${pkg}" -execdir reprepro \
      -b "${DISTRO_DIR}" \
      "include${pkg}" \
     "${DISTRO_CN}" {} \;
    find "${tmp_dir}" -type f -name "*\.${pkg}" -execdir reprepro \
      -C extras \
      -b "${DISTRO_DIR}" \
      "include${pkg}" \
     "${DISTRO_CN}" {} \;
  done

  pushd "${tmp_dir}"
  apt-get -y source ubuntu-keyring
  pushd ubuntu-keyring-*
  gpg --import < keyrings/ubuntu-archive-keyring.gpg
  gpg --yes --output=keyrings/ubuntu-archive-keyring.gpg \
    --export "Ubuntu" "Mirantis"
  dpkg-buildpackage -rfakeroot -m"Mirantis"
  cp -f keyrings/ubuntu-archive-keyring.gpg "${tmp_dir}"
  popd
  reprepro -b "${DISTRO_DIR}" remove "${DISTRO_CN}" ubuntu-keyring-udeb
  reprepro -b "${DISTRO_DIR}" includeudeb "${DISTRO_CN}" \
    ubuntu-keyring-udeb*.udeb

  unsquashfs -n "${DISTRO_DIR}/install/filesystem.squashfs"
  cp -f ubuntu-archive-keyring.gpg \
    squashfs-root/usr/share/keyrings/ubuntu-archive-keyring.gpg
  cp -f ubuntu-archive-keyring.gpg \
    squashfs-root/etc/apt/trusted.gpg
  cp -f ubuntu-archive-keyring.gpg \
    squashfs-root/var/lib/apt/keyrings/ubuntu-archive-keyring.gpg
  du -sx --block-size=1 squashfs-root/ | \
    cut -f 1 > "${DISTRO_DIR}/install/filesystem.size"
  mksquashfs squashfs-root/ "${DISTRO_DIR}/install/filesystem.squashfs"
  popd

  find "${DISTRO_DIR}/" -type f -print0 | \
    xargs -0 md5sum > "${DISTRO_DIR}/md5sum.txt"
}

create_iso() {
  apt-get -y install genisoimage
  genisoimage \
   -V 'MMS Ubuntu Install CD' \
   -D \
   -r \
   -cache-inodes \
   -J \
   -l \
   -b isolinux/isolinux.bin \
   -c isolinux/boot.cat \
   -no-emul-boot \
   -boot-load-size 4 \
   -boot-info-table \
   -o "${HOME}/image.iso" \
   "${DISTRO_DIR}"
}

mount /dev/cdrom /media/cdrom
cp -rT /media/cdrom/ "${DISTRO_DIR}"

#apt-cdrom -m -d=/media/cdrom add

# Add Docker's APT repository
#repo='deb http://apt.dockerproject.org/repo ubuntu-trusty main'
#echo "${repo}" > /etc/apt/sources.list.d/docker.list
#apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 \
#  --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

#apt-get clean
#apt-get update

#packages='docker-engine ansible'

#apt-get -qq --print-uris install ${packages} | \
#  grep -v 'cdrom:\[' | \
#  cut -d ' ' -f 1 | \
#  sed -r "s/(^'|'$)//g" > /tmp/packages.txt

[[ -n "${PRESEED}" ]] && inject_preseed
create_repo
create_iso


sleep 18000
