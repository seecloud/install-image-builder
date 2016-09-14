#!/usr/bin/env bash

readonly GPG_UID DEB_PACKAGES PY_PACKAGES \
  DISTRO_DIR="$(mktemp -d)" DISTRO_CN="$(lsb_release -cs)"

config_preseed() {
  cp -f "${HOME}/preseed.cfg" "${DISTRO_DIR}/preseed/"

  cat > "${DISTRO_DIR}/isolinux/txt1.cfg" << EOF
default mms
label mms
  menu label ^Install MMS version of Ubuntu Server
  kernel /install/vmlinuz
  append  file=/cdrom/preseed/preseed.cfg vga=788 initrd=/install/initrd.gz quiet --
label check
  menu label ^Check disc for defects
  kernel /install/vmlinuz
  append   MENU=/bin/cdrom-checker-menu vga=788 initrd=/install/initrd.gz quiet --
label memtest
  menu label Test ^memory
  kernel /install/mt86plus
label hd
  menu label ^Boot from first hard disk
  localboot 0x80"
EOF
  sed 's/ txt.cfg/ txt1.cfg/' -i "${DISTRO_DIR}/isolinux/menu.cfg"
}

add_packages() {
  local -r tmp_dir="$(mktemp -d)" pypi_dir="${DISTRO_DIR}/pypi"

  apt-cdrom -m -d=/media/cdrom add

  # Add Docker repository
  echo "deb http://apt.dockerproject.org/repo ubuntu-${DISTRO_CN} main" > \
    /etc/apt/sources.list.d/docker.list
  apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 \
    --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

  # Add Ansible repository
  apt-add-repository -y ppa:ansible/ansible

  apt-get clean
  apt-get update

  # Download required deb packages
  apt-get -qq --print-uris install ${DEB_PACKAGES} | \
    grep -v 'cdrom:\[' | \
    cut -d ' ' -f 1 | \
    sed -r "s/(^'|'$)//g" | \
    wget -q -P "${tmp_dir}" -i -

  # Download required Python packages and create a PyPI repository
  apt-get -y install python-pip
  mkdir -p "${pypi_dir}"
  for py_package in ${PY_PACKAGES}; do
    pip install --download="${pypi_dir}" "${py_package}"
  done
  pip install pip2pi
  dir2pi "${pypi_dir}"

  apt-get -y install reprepro fakeroot dpkg-dev squashfs-tools

  sed '/^SignWith:/d' -i "${HOME}/config/reprepro/conf/distributions"
  echo "SignWith: ${GPG_UID}" >> "${HOME}/config/reprepro/conf/distributions"
  cp -rf "${HOME}"/config/reprepro/* "${DISTRO_DIR}"

  rm -rf "${DISTRO_DIR}/dists/${DISTRO_CN}"

  for pkg in deb udeb; do
    find "${DISTRO_DIR}/pool" -type f -name "*\.${pkg}" -execdir reprepro \
      -s \
      -b "${DISTRO_DIR}" \
      "include${pkg}" \
     "${DISTRO_CN}" {} \;
    find "${tmp_dir}" -type f -name "*\.${pkg}" -execdir reprepro \
      -C extras \
      -s \
      -b "${DISTRO_DIR}" \
      "include${pkg}" \
     "${DISTRO_CN}" {} \;
  done

  pushd "${tmp_dir}"
  apt-get -y source ubuntu-keyring
  pushd ubuntu-keyring-*
  gpg --import < keyrings/ubuntu-archive-keyring.gpg
  gpg --yes --output=keyrings/ubuntu-archive-keyring.gpg \
    --export 'Ubuntu' "${GPG_UID}"
  dpkg-buildpackage -rfakeroot -m"${GPG_UID}"
  cp -f keyrings/ubuntu-archive-keyring.gpg "${tmp_dir}"
  popd
  reprepro -s -b "${DISTRO_DIR}" remove "${DISTRO_CN}" ubuntu-keyring-udeb
  reprepro -s -b "${DISTRO_DIR}" includeudeb "${DISTRO_CN}" \
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
  rm -f "${DISTRO_DIR}/install/filesystem.squashfs"
  mksquashfs squashfs-root/ "${DISTRO_DIR}/install/filesystem.squashfs"
  popd

  rm -rf "${DISTRO_DIR}/"{conf,db}

  pushd "${DISTRO_DIR}"
  find "." -type f -print0 | xargs -0 md5sum > md5sum.txt
  popd
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

main() {
  mount /dev/cdrom /media/cdrom
  cp -rT /media/cdrom/ "${DISTRO_DIR}"

  [[ -f "${HOME}/preseed.cfg" ]] && config_preseed
  [[ -n "${GPG_UID}" &&
    -n "${DEB_PACKAGES}" &&
    -n "${PY_PACKAGES}" &&
    -f "${HOME}/.gnupg/pubring.gpg" &&
    -f "${HOME}/.gnupg/secring.gpg" ]] && add_packages

  create_iso
}

main "$@"

#sleep 18000
