#!/bin/bash -x

readonly RPM_PACKAGES PY_PACKAGES \
  DISTRO_DIR="$(mktemp -d)"

# update yum cache
function yum_update_cache()
{
  local yum_config
  local disable_fastmirror
  yum_config=${1:-"/etc/yum.conf"}
  disable_fastmirror=${2:-""}
  if [ "${disable_fastmirror}" == "1" ]; then
    disable_fastmirror="--disableplugin=fastestmirror"
  fi
  yum -c ${yum_config} clean all
  yum -c ${yum_config} ${disable_fastmirror} makecache
}
# prepare
function mkprep()
{
  yum install -y epel-release
  yum_update_cache
  rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
  yum install -y createrepo yum-utils genisoimage rsync
}
# copy required data from installation media
function cp_iso_data()
{
  local destination
  local cdpath
  local compsfile
  destination=${1}
  cdpath="/media/cdrom"
  mkdir -p ${destination}/{images,ks,LiveOS,Packages,postinstall}
  cp ${cdpath}/.discinfo ${destination}/ || exit $?
  echo "ALL" >> ${destination}/.discinfo
  cp ${cdpath}/isolinux/* ${destination}/ || exit $?
  cp ${cdpath}/LiveOS/* ${destination}/LiveOS/ || exit $?
  rsync -av ${cdpath}/images/ ${destination}/images/ || exit $?
  # copy gpg keys
  find ${cdpath} -name "*GPG-KEY*" -exec cp {} ${destination}/ \;
  compsfile=$(find "${cdpath}/repodata/" -name "*comps.xml.gz" | head -n1)
  if [ -f ${compsfile} ]; then
    gunzip ${compsfile} -c > "${destination}/comps.xml"
  else
    echo "comps file not found!"
    exit 1
  fi
}

# create repodata
function mkrepo()
{
  local repopath
  local params
  repopath=${1}
  shift
  params=${*:-''}
  if [ ! -d ${repopath} ]; then
    echo "Repository path wrong or emply!"
    exit 1
  fi
  rm -rf ${repopath}/repodata
  createrepo -v ${params} ${repopath} || exit $?
}

# main
function main() {
  # temp yum
  local tmp_yumroot
  local tmp_yumcache
  local tmp_yumcache_updates
  local tmp_yumrepos_updates
  # other dirs
  local builddir
  local fakeinstallroot
  local tmp_downloaded_repo
  local tmp_downloaded_packages

  tmp_yumroot="${DISTRO_DIR}/yum.d"
  tmp_yumcache="${tmp_yumroot}/yumcache0"
  tmp_yumcache_updates="${tmp_yumroot}/yumcache1"
  tmp_yumrepos_updates="${tmp_yumroot}/repos"

  builddir="${DISTRO_DIR}/isolinux"
  tmp_downloaded_packages="${DISTRO_DIR}/downloaded_pkgs"
  tmp_downloaded_repo="${DISTRO_DIR}/downloaded_repo"
  fakeinstallroot="${DISTRO_DIR}/froot"

  mkdir -p ${builddir}
  mkdir -p ${fakeinstallroot}
  mkdir -p ${tmp_downloaded_repo}/Packages
  mkdir -p ${tmp_downloaded_packages}
  mkdir -p ${tmp_yumroot}
  mkdir -p ${tmp_yumcache}
  mkdir -p ${tmp_yumcache_updates}
  mkdir -p ${tmp_yumrepos_updates}
  mkdir -p /media/cdrom
  #mount install media
  mount /dev/cdrom /media/cdrom
  # get epel gpg key
  curl -L http://fedora-mirror01.rbc.ru/pub/epel/RPM-GPG-KEY-EPEL-7  --output ${builddir}/RPM-GPG-KEY-EPEL-7
  # gen yum.conf files
  cat <<EOF > "${tmp_yumroot}/yum.conf"
[main]
cachedir=${tmp_yumcache}
keepcache=0
debuglevel=2
logfile=${tmp_yumroot}/yum-work.log
exactarch=1
obsoletes=1
gpgcheck=1
plugins=1
installonly_limit=5
bugtracker_url=http://bugs.centos.org/set_project.php?project_id=23&ref=http://bugs.centos.org/bug_report_page.php?category=yum
distroverpkg=centos-release
EOF
# yum for updated packages
  cat <<EOF > "${tmp_yumroot}/yum2.conf"
[main]
cachedir=${tmp_yumcache_updates}
reposdir=${tmp_yumrepos_updates}
keepcache=0
debuglevel=2
logfile=${tmp_yumroot}/yum-updates.log
exactarch=1
obsoletes=1
gpgcheck=1
plugins=1
installonly_limit=5
bugtracker_url=http://bugs.centos.org/set_project.php?project_id=23&ref=http://bugs.centos.org/bug_report_page.php?category=yum
distroverpkg=centos-release
EOF
# cdrom
  cat <<EOF > "${tmp_yumrepos_updates}/cdrom.repo"
[cdrom]
name=CentOS-\$releasever - Media
baseurl=file:///media/cdrom/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF
# repository with downloaded packages
  cat <<EOF > "${tmp_yumrepos_updates}/downloaded.repo"
[downloaded]
name=CentOS-\$releasever - downloaded files
baseurl=file://${tmp_downloaded_repo}
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF

  # populating with initital data from iso
  cp_iso_data ${builddir}
  # gen yum cache
  yum-config-manager --enable c7-media > /dev/null
  yum repolist
  yum-config-manager --enable updates > /dev/null
  rm -f /etc/yum.repos.d/downloaded.repo
  yum_update_cache ${tmp_yumroot}/yum.conf
  # downloading updated packages
  repotrack -c ${tmp_yumroot}/yum.conf -a x86_64 -r base -r extras -r epel -r updates -p ${tmp_downloaded_packages} ${RPM_PACKAGES} || exit $?
  # clean 32 bit packages
  rm -f ${tmp_downloaded_packages}/*.i686.rpm
  rsync -avlp "${tmp_downloaded_packages}/" "${tmp_downloaded_repo}/Packages/"
  mkrepo ${tmp_downloaded_repo}
  # updating & checking temporary repo
  yum_update_cache ${tmp_yumroot}/yum2.conf
  repoclosure -c ${tmp_yumroot}/yum2.conf -r downloaded -r cdrom || exit $?
# UPDATING BASE PACKAGE LIST FROM CDROM
  # add deownloaded into default repos
  cp -f ${tmp_yumrepos_updates}/downloaded.repo /etc/yum.repos.d/
  # update for packages from installation media
  yum_update_cache ${tmp_yumroot}/yum.conf
  repotrack -c ${tmp_yumroot}/yum.conf -a x86_64 -r base -r updates -p ${tmp_downloaded_packages} $(repoquery --disablerepo=* --enablerepo=c7-media --qf='%{NAME}' '*') || exit $?
  # clean 32 bit packages
  rm -f ${tmp_downloaded_packages}/*.i686.rpm
  # updating & checking temporary repo
  rsync -avlp "${tmp_downloaded_packages}/" "${tmp_downloaded_repo}/Packages/"
  mkrepo ${tmp_downloaded_repo}
  # updaing temp
  yum_update_cache ${tmp_yumroot}/yum2.conf
  repoclosure -c ${tmp_yumroot}/yum2.conf -r downloaded -r cdrom || exit $?
  # add packages into future ISO repo
  rsync -avlp "${tmp_downloaded_packages}/" "${builddir}/Packages/" || exit $?
  mkrepo "${builddir}" "-g ${builddir}/comps.xml"
  yum-config-manager --disable downloaded > /dev/null
  # creating kickstart
  cat <<EOF > "${builddir}/ks/ks.cfg"
auth --enableshadow --passalgo=sha512
install
cdrom
text
skipx
network --bootproto=dhcp --device=eth0

lang en_US.UTF-8
keyboard us
timezone --utc Etc/UTC

rootpw --iscrypted \$6\$M0SIo\$zvOx4Mb2URPVFCQdthSO.giQrdfKMfghwTtuS7dK/wRmgMikCkN85Wu0d2TzaHa4GZd1985Yz9tYaTuqmkZgV0
firewall --enabled --ssh
zerombr
clearpart --all --initlabel
autopart --type=plain
bootloader --timeout=2

reboot

%packages
@core
which
# mandatory packages in the @core group
-btrfs-progs
-iprutils
-kexec-tools
-plymouth
# default packages in the @core group
-*-firmware
-dracut-config-rescue
-kernel-tools
-libsysfs
-microcode_ctl
-NetworkManager*
-postfix
# custom packages
$(for rpm in ${RPM_PACKAGES};do echo $rpm;done)
%end
%post --nochroot
#!/bin/sh
set -x -v
exec 1>/mnt/sysimage/root/kickstart-stage1.log 2>&1
echo "==> copying EPEL-7 key..."
cp /run/install/repo/RPM-GPG-KEY-EPEL-7 /mnt/sysimage/etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
%end
%post
#!/bin/sh
set -x -v
exec 1>/root/kickstart-stage2.log 2>&1
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
sleep 30
%end
EOF
  # updating iso menu
  sed -r -i -e 's/^timeout [0-9]+/timeout 60/' -e '/menu default/d' ${builddir}/isolinux.cfg
  sed -r -i -e "s/label check/label custom\n menu label ^Unattended install\n  menu default\n  kernel vmlinuz \n\
  append initrd=initrd.img inst.stage2=hd:LABEL=CentOS\\\\x207\\\\x20x86_64\
  biosdevname=0 net.ifnames=0 inst.ks=cdrom:\/dev\/cdrom:\/ks\/ks.cfg \n\nlabel check/" \
  ${builddir}/isolinux.cfg
  # generating iso
  mkisofs -o "/tmp/centos.iso" -b isolinux.bin -c boot.cat -no-emul-boot -V 'CentOS 7 x86_64' -boot-load-size 4 -boot-info-table -R -J -v -T "${builddir}/" | tee /tmp/mkisofs.log
  # cleanup
  rm -rf $DISTRO_DIR
}
#
mkprep
main
