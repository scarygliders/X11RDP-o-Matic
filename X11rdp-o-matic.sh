#!/bin/bash
set -u # warn undefined variables
# vim:ts=2:sw=2:sts=0:number:expandtab

# Automatic Xrdp/X11rdp Compiler/Installer
# a.k.a. ScaryGliders X11rdp-O-Matic
#
# Version 3.11
#
# Version release date : 20140927
########################(yyyyMMDD)
#
# Will run on Debian-based systems only at the moment. RPM based distros perhaps some time in the future...
#
# Copyright (C) 2012-2014, Kevin Cave <kevin@scarygliders.net>
# With contributions and suggestions from other kind people - thank you!
#
# ISC License (ISC)
#
# Permission to use, copy, modify, and/or distribute this software for any purpose with
# or without fee is hereby granted, provided that the above copyright notice and this
# permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO
# THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
# DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
# AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION
# WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
export LANG=C
trap user_interrupt_exit SIGINT

if [ $UID -eq 0 ] ; then
  # write to stderr 1>&2
  echo "${0}:  Never run this utility as root." 1>&2
  echo 1>&2
  echo "This script will gain root privileges via sudo on demand, then type your password." 1>&2
  exit 1
fi

if ! hash sudo 2> /dev/null ; then
  # write to stderr 1>&2
  echo "${0}: sudo not found." 1>&2
  echo 1>&2
  echo 'This utility requires sudo to gain root privileges on demand.' 1>&2
  echo 'run `apt-get install sudo` in root privileges before run this utility.' 1>&2
  exit 1
fi

LINE="----------------------------------------------------------------------"

# xrdp repository
GH_ACCOUNT=neutrinolabs
GH_PROJECT=xrdp
GH_BRANCH=master
GH_URL=https://github.com/${GH_ACCOUNT}/${GH_PROJECT}.git

# working directories and logs
WRKDIR=$(mktemp --directory --suffix .X11RDP-o-Matic)
BASEDIR=$(dirname $(readlink -f $0))
PKGDIR=${BASEDIR}/packages
PATCHDIR=${BASEDIR}/patch
PIDFILE=${BASEDIR}/.PID
APT_LOG=${WRKDIR}/apt.log
BUILD_LOG=${WRKDIR}/build.log
SUDO_LOG=${WRKDIR}/sudo.log

# packages to run this utility
META_DEPENDS=(lsb-release rsync git build-essential dh-make wget)
XRDP_CONFIGURE_ARGS=(--prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-fuse --enable-jpeg --enable-opus)
XRDP_BUILD_DEPENDS=(debhelper autoconf automake dh-systemd libfuse-dev libjpeg-dev libopus-dev libpam0g-dev libssl-dev libtool libx11-dev libxfixes-dev libxrandr-dev pkg-config)
X11RDP_BUILD_DEPENDS=(autoconf automake libtool flex bison python-libxml2 libxml2-dev gettext intltool xsltproc make gcc g++ xutils-dev xutils)
XORGXRDP_BUILD_DEPENDS=(automake autoconf libtool pkg-config nasm xserver-xorg-dev)

ARCH=$(dpkg --print-architecture)
RELEASE=1 # release number for debian packages
X11RDPBASE=/opt/X11rdp

# flags
PARALLELMAKE=true   # Utilise all available CPU's for compilation by default.
CLEANUP=false       # Keep the x11rdp and xrdp sources by default - to remove
                    # requires --cleanup command line switch
INSTALL_PKGS=true   # Install xrdp and x11rdp on this system
BUILD_X11RDP=true   # Build and package x11rdp
GIT_USE_HTTPS=true  # Use firewall-friendry https:// instead of git:// to fetch git submodules

# check if the system is using systemd or not
[ -z "$(pidof systemd)" ] && \
  USING_SYSTEMD=false || \
  USING_SYSTEMD=true

# Declare a list of packages required to download sources/compile them...
REQUIREDPACKAGES=(build-essential checkinstall automake git
git-core libssl-dev libpam0g-dev zlib1g-dev libtool libx11-dev libxfixes-dev
pkg-config flex bison libxml2-dev intltool xsltproc xutils-dev python-libxml2
g++ xutils libfuse-dev libxrandr-dev libdrm-dev libpixman-1-dev
x11proto-xf86dri-dev
x11proto-video-dev
x11proto-resource-dev
x11proto-dmx-dev
x11proto-xf86dga-dev
x11proto-xinerama-dev
x11proto-render-dev
x11proto-bigreqs-dev
x11proto-kb-dev
x11proto-randr-dev
x11proto-gl-dev
x11proto-record-dev
x11proto-input-dev
x11proto-fixes-dev
x11proto-xf86vidmode-dev
x11proto-xext-dev
x11proto-scrnsaver-dev
x11proto-damage-dev
x11proto-xf86bigfont-dev
x11proto-composite-dev
x11proto-core-dev
x11proto-xcmisc-dev
x11proto-dri2-dev
x11proto-fonts-dev
libgl1-mesa-dev libxkbfile-dev libxfont-dev libpciaccess-dev dh-make gettext
xfonts-utils)

# libtool binaries are separated to libtool-bin package since Ubuntu 15.04
# if libtool-bin package exists, add it to REQUIREDPACKAGES
apt-cache search ^libtool-bin | grep -q libtool-bin && \
  REQUIREDPACKAGES+=(libtool-bin) XRDP_BUILD_DEPENDS+=(libtool-bin) X11RDP_BUILD_DEPENDS+=(libtool-bin)

#############################################
# Common function declarations begin here...#
#############################################

SUDO_CMD()
{
  # sudo's password prompt timeouts 5 minutes by most default settings
  # to avoid exit this script because of sudo timeout
  echo_stderr
  # not using echo_stderr here because output also be written $SUDO_LOG
  echo "Following command will be executed via sudo:" | tee -a $SUDO_LOG 1>&2
  echo "	$@" | tee -a $SUDO_LOG 1>&2
  while ! sudo -v; do :; done
  sudo $@ | tee -a $SUDO_LOG
  return ${PIPESTATUS[0]}
}

echo_stderr()
{
  echo $@ 1>&2
}

error_exit()
{
  echo_stderr; echo_stderr
  echo_stderr "Oops, something going wrong around line: $BASH_LINENO"
  echo_stderr "See logs to get further information:"
  echo_stderr "	$BUILD_LOG"
  echo_stderr "	$SUDO_LOG"
  echo_stderr "	$APT_LOG"
  echo_stderr "Exitting..."
  [ -f "${PIDFILE}" ] && [ "$(cat "${PIDFILE}")" = $$ ] && rm -f "${PIDFILE}"
  exit 1
}

clean_exit()
{
  [ -f "${PIDFILE}" ] && [ "$(cat "${PIDFILE}")" = $$ ] && rm -f "${PIDFILE}"
  exit 0
}

user_interrupt_exit()
{
  echo_stderr; echo_stderr
  echo_stderr "Script stopped due to user interrupt, exitting..."
  cd "$BASEDIR"
  [ -f "${PIDFILE}" ] && [ "$(cat "${PIDFILE}")" = $$ ] && rm -f "${PIDFILE}"
  exit 1
}

# call like this: install_required_packages ${PACKAGES[@]}
install_required_packages()
{
  for f in $@
  do
    echo -n "Checking for ${f}... "
    check_if_installed $f
    if [ $? -eq 0 ]; then
      echo "yes"
    else
      echo "no"
      echo -n "Installing ${f}... "
      SUDO_CMD apt-get -y install $f >> $APT_LOG && echo "done" || error_exit
    fi
  done
}

# check if given package is installed
check_if_installed()
{
  # if not installed, the last command's exit code will be 1
  dpkg-query -W --showformat='${Status}\n' "$1" 2>/dev/null  \
    | grep -v -q -e "deinstall ok" -e "not installed"  -e "not-installed"
}

install_package()
{
  SUDO_CMD apt-get -y install "$1" >> $APT_LOG || error_exit
}

# change dh_make option depending on if dh_make supports -y option
dh_make_y()
{
  dh_make -h | grep -q -- -y && \
    DH_MAKE_Y=true || DH_MAKE_Y=false

  if $DH_MAKE_Y
  then
    dh_make -y $@
  else
    echo | dh_make $@
  fi
}

# Get list of available branches from remote git repository
get_branches()
{
  echo $LINE
  echo "Obtaining list of available branches..."
  echo $LINE
  BRANCHES=$(git ls-remote --heads "$GH_URL" | cut -f2 | cut -d "/" -f 3)
  echo $BRANCHES
  echo $LINE
}

first_of_all()
{
  clear

  if [ -f "${PIDFILE}" ]; then
    echo_stderr "Another instance of $0 is already running." 2>&1
    error_exit
  else
    echo $$ > "${PIDFILE}"
  fi

  echo 'Allow X11RDP-o-Matic to gain root privileges.'
  echo 'Type your password if required.'
  sudo -v

  SUDO_CMD apt-get update >> $APT_LOG || error_exit
}

parse_commandline_args()
{
# If first switch = --help, display the help/usage message then exit.
  if [ $1 = "--help" ]
  then
    clear
    echo "usage: $0 OPTIONS

OPTIONS
-------
  --help             : show this help.
  --justdoit         : perform a complete compile and install with sane defaults and no user interaction.
  --branch <branch>  : use one of the available xrdp branches listed below...
                       Examples:
                       --branch v0.8    - use the 0.8 branch.
                       --branch master  - use the master branch. <-- Default if no --branch switch used.
                       --branch devel   - use the devel branch (Bleeding Edge - may not work properly!)
                       Branches beginning with "v" are stable releases.
                       The master branch changes when xrdp authors merge changes from the devel branch.
  --nocpuoptimize    : do not change X11rdp build script to utilize more than 1 of your CPU cores.
  --cleanup          : remove X11rdp / xrdp source code after installation. (Default is to keep it).
  --noinstall        : do not install anything, just build the packages
  --nox11rdp         : only build xrdp, do not build the x11rdp backend
  --withdebug        : build with debug enabled
  --withneutrino     : build the neutrinordp module
  --withkerberos     : build support for kerberos
  --withxrdpvr       : build the xrdpvr module
  --withnopam        : don't include PAM support
  --withpamuserpass  : build with pam userpass support
  --withfreerdp      : build the freerdp1 module"
    get_branches
    rmdir "${WRKDIR}"
    exit
  fi

  # Parse the command line for any arguments
  while [ $# -gt 0 ]; do
  case "$1" in
    --justdoit)
      echo
      echo "NOTICE: --justdoit options is deprecated since it is now default behaviour"
      echo
      echo "Okay, will just do the install from start to finish with no user interaction..."
      echo $LINE
      ;;
    --branch)
      get_branches
      ok=0
      for check in ${BRANCHES[@]}
      do
        if [ "$check" = "$2" ]
        then
          ok=1
        fi
      done
      if [ $ok -eq 0 ]
      then
        echo "**** Error detected in branch selection. Argument after --branch was : $2 ."
        echo "**** Available branches : "$BRANCHES
        exit 1
      fi
      GH_BRANCH="$2"
      echo "Using branch ==>> ${GH_BRANCH} <<=="
      if [ "$GH_BRANCH" = "devel" ]
      then
        echo "Note : using the bleeding-edge version may result in problems :)"
      fi
      echo $LINE
      shift
      ;;
    --nocpuoptimize)
      PARALLELMAKE=false
      echo "Will not utilize additional CPU's for compilation..."
      echo $LINE
      ;;
    --cleanup)
      CLEANUP=true
      echo "Will remove the xrdp and x11rdp sources in the working directory after compilation/installation..."
      echo $LINE
      ;;
    --noinstall)
      INSTALL_PKGS=false
      echo "Will not install anything on the system but will build the packages"
      echo $LINE
      ;;
    --nox11rdp)
      BUILD_X11RDP=false
      echo "Will not build and package x11rdp"
      echo $LINE
      ;;
    --withdebug)
      XRDP_CONFIGURE_ARGS+=(--enable-xrdpdebug)
      ;;
    --withneutrino)
      XRDP_CONFIGURE_ARGS+=(--enable-neutrinordp)
      ;;
    --withkerberos)
      XRDP_CONFIGURE_ARGS+=(--enable-kerberos)
      ;;
    --withxrdpvr)
      XRDP_CONFIGURE_ARGS+=(--enable-xrdpvr)
      XRDP_BUILD_DEPENDS+=(libavcodec-dev libavformat-dev)
      ;;
    --withnopam)
      XRDP_CONFIGURE_ARGS+=(--disable-pam)
      ;;
    --withpamuserpass)
      XRDP_CONFIGURE_ARGS+=(--enable-pamuserpass)
      ;;
    --withfreerdp)
      XRDP_CONFIGURE_ARGS+=(--enable-freerdp1)
      XRDP_BUILD_DEPENDS+=(libfreerdp-dev)
      ;;
  esac
  shift
  done
}

clone()
{
  local CLONE_DEST="${WRKDIR}/xrdp"
  echo -n 'Cloning source code... '
 
  if [ ! -d "$CLONE_DEST" ]; then
    if $GIT_USE_HTTPS; then
      git clone ${GH_URL} --branch ${GH_BRANCH} ${CLONE_DEST} >> $BUILD_LOG 2>&1 || error_exit
      sed -i -e 's|git://|https://|' ${CLONE_DEST}/.gitmodules ${CLONE_DEST}/.git/config
      (cd $CLONE_DEST && git submodule update --init --recursive) >> $BUILD_LOG 2>&1
    else
      git clone --resursive ${GH_URL} --branch ${GH_BRANCH} ${CLONE_DEST} >> $BUILD_LOG 2>&1 || error_exit
    fi
    echo 'done'
  else
    echo 'already exists'
  fi
}

compile_X11rdp()
{
  cd "$WRKDIR/xrdp/xorg/X11R7.6/"
  SUDO_CMD sh buildx.sh "$X11RDPBASE" >> $BUILD_LOG 2>&1 || error_exit
}

package_X11rdp()
{
  X11RDP_DEB="x11rdp_${X11RDP_VERSION}-${RELEASE}_${ARCH}.deb"

  if [ -f "$WRKDIR/xrdp/xorg/debuild/debX11rdp.sh" ]
  then
    cd "$WRKDIR/xrdp/xorg/debuild"
    ./debX11rdp.sh "$X11RDP_VERSION" "$RELEASE" "$X11RDPBASE" "$WRKDIR" || error_exit
  fi

  cp "${WRKDIR}/${X11RDP_DEB}" "${PKGDIR}" || error_exit
}

# Package xrdp using dh-make...
compile_xrdp()
{
  XRDP_DEB="xrdp_${XRDP_VERSION}-${RELEASE}_${ARCH}.deb" 
  XORGXRDP_DEB="xorgxrdp_${XRDP_VERSION}-${RELEASE}_${ARCH}.deb" 

  echo $LINE
  echo "Using the following xrdp configuration : "${XRDP_CONFIGURE_ARGS[@]}
  echo $LINE
  echo "Preparing xrdp source to make a Debian package..."
  echo $LINE

  # Step 1: Link xrdp dir to xrdp-$VERSION for dh_make to work on...
  rsync -a --delete -- "${WRKDIR}/xrdp/" "${WRKDIR}/xrdp-${XRDP_VERSION}" 

  # Step 2 : Use dh-make to create the debian directory package template...
  cd "${WRKDIR}/xrdp-${XRDP_VERSION}"
  dh_make_y --single --copyright apache --createorig >> $BUILD_LOG 2>&1 || error_exit

  # Step 3: Run the bootstrap and configure scripts
  #./bootstrap >> $BUILD_LOG || error_exit
  #./configure "${XRDP_CONFIGURE_ARGS[@]}" >> $BUILD_LOG || error_exit

  # Step 4 : edit/configure the debian directory...
  rm debian/*.{ex,EX} debian/README.{Debian,source}
  cp "${BASEDIR}/debian/"{control,docs,postinst,prerm,install,socksetup,startwm.sh} debian/
  cp -r "${BASEDIR}/debian/"patches debian/
  cp COPYING debian/copyright
  cp readme.txt debian/README
  sed -e "s|%%XRDP_CONFIGURE_ARGS%%|${XRDP_CONFIGURE_ARGS[*]}|g" \
       "${BASEDIR}/debian/rules.in" > debian/rules
  chmod 0755 debian/rules

  # Step 5 : run dpkg-buildpackage to compile xrdp and build a package...
  echo $LINE
  echo "Preparation complete. Building and packaging xrdp..."
  echo $LINE
  dpkg-buildpackage -uc -us -tc -rfakeroot >> $BUILD_LOG  2>&1 || error_exit
  cp "${WRKDIR}/${XRDP_DEB}" "${PKGDIR}" || error_exit
  cp "${WRKDIR}/${XORGXRDP_DEB}" "${PKGDIR}" || error_exit
}

calc_cpu_cores()
{
  Cores=$(nproc)
  if [ $Cores -gt 1 ]
  then
    let "MakesystemWorkHarder = $Cores + 1"
    makeCommand="make -j $MakesystemWorkHarder"
  else
    PARALLELMAKE=false
  fi
}

cpu_cores()
{
  if [ ! -e "$WRKDIR/PARALLELMAKE" ] # No need to perform this if for some reason we've been here before...
  then
    if $PARALLELMAKE
    then
      sed -i -e "s/make -j 1/$makeCommand/g" "$PATCHDIR/buildx_patch.diff"
      touch "$WRKDIR/PARALLELMAKE"
    fi
  fi
}

# bran new version calculation
# new version number includes git last commit date, hash and branch.
bran_new_calculate_version_num()
{
  local _PWD=$PWD
  cd ${WRKDIR}/xrdp || error_exit
  local _XRDP_VERSION=$(grep xrdp readme.txt| head -1 | cut -d ' ' -f 2)
  local _XRDP_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  # hack for git 2.1.x
  # in latest git, this can be written: git log -1 --date=format:%Y%m%d --format="~%cd+git%h" .
  local _XRDP_DATE_HASH=$(git log -1 --date=short --format="~%cd+git%h" . | tr -d -)
  local _X11RDP_DATE_HASH=$(git log -1 --date=short --format="~%cd+git%h" xorg/X11R7.6 | tr -d -)
  #local _XORGXRDP_DATE_HASH=$(git log -1 --date=short --format="~%cd+git%h" xorgxrdp | tr -d -)
  cd ${_PWD} || error_exit

  XRDP_VERSION=${_XRDP_VERSION}${_XRDP_DATE_HASH}+${_XRDP_BRANCH}
  X11RDP_VERSION=${_XRDP_VERSION}${_X11RDP_DATE_HASH}+${_XRDP_BRANCH}
  #XORGXRDP_VERSION=${_XRDP_VERSION}${_XORGXRDP_DATE_HASH}+${_XRDP_BRANCH}
  XORGXRDP_VERSION=${XRDP_VERSION}

  echo -e "\t" xrdp=${XRDP_VERSION}
  echo -e "\t" x11rdp=${X11RDP_VERSION}
  echo -e "\t" xorgxrdp=${XORGXRDP_VERSION}
}

# Make a directory, to which the X11rdp build system will
# place all the built binaries and files.
make_X11rdp_env()
{
  $BUILD_X11RDP || return

  if [ -e "$X11RDPBASE" -a "$X11RDPBASE" != "/" ]
  then
    remove_installed_packages x11rdp
    SUDO_CMD rm -rf "$X11RDPBASE" || error_exit
    SUDO_CMD mkdir -p "$X11RDPBASE" || error_exit
  fi
}

# Alter xrdp source code Makefile.am so the PID file is now in /var/run/xrdp/
# Also patch rdp Makefile to tell Ubuntu linker to include GL symbols - pesky Ubuntu...
alter_xrdp_source()
{
  cd "$WRKDIR"
  # Patch Jay's buildx.sh.
  # This will patch the make command for parallel makes if that was requested,
  # which should speed up compilation. It will make a backup copy of the original buildx.sh.
  if $PARALLELMAKE
  then
    patch -b -d "$WRKDIR/xrdp/xorg/X11R7.6" buildx.sh < "$PATCHDIR/buildx_patch.diff" >> $BUILD_LOG || error_exit
  fi

  # Patch rdp Makefile
  patch -b -d "$WRKDIR/xrdp/xorg/X11R7.6/rdp" Makefile < "$PATCHDIR/rdp_Makefile.patch" >> $BUILD_LOG  || error_exit

  # Patch v0.7 buildx.sh, as the file download location for Mesa has changed...
  if [[ $GH_BRANCH = "v0.7"* ]] # branch v0.7 has a moved libmesa
  then
      echo "Patching mesa download location..."
      patch -b -d "$WRKDIR/xrdp/xorg/X11R7.6" buildx.sh < "$PATCHDIR/mesa.patch" || error_exit
  fi
}

install_generated_packages()
{
  $INSTALL_PKGS || return # do nothing if "--noinstall"

  if ${BUILD_X11RDP}; then
    remove_installed_packages x11rdp
    echo -n 'Installing built x11rdp... '
    SUDO_CMD dpkg -i "${PKGDIR}/${X11RDP_DEB}" || error_exit
    echo 'done'
  fi

  remove_installed_packages xrdp xorgxrdp
  echo -n 'Installing built xrdp... '
  SUDO_CMD dpkg -i "${PKGDIR}/${XRDP_DEB}" || error_exit
  echo 'done'
  echo -n 'Installing built xorgxrdp... '
  SUDO_CMD dpkg -i "${PKGDIR}/${XORGXRDP_DEB}" || error_exit
  echo 'done'
}

download_compile()
{
  clone
  if $PARALLELMAKE
  then
    cpu_cores
  fi

  alter_xrdp_source # Patches the downloaded source

  # New method...
  # Compiles & packages using dh_make and dpkg-buildpackage
  compile_xrdp

  if $BUILD_X11RDP
  then
    compile_X11rdp
    package_X11rdp
  fi
}

remove_installed_packages()
{
  for f in $@; do
    echo -n "Removing installed ${f}... "
    check_if_installed ${f}
    if [ $? -eq 0 ]; then
      SUDO_CMD apt-get -y remove ${f} || error_exit
    fi
    echo "done"
  done
}

check_for_opt_directory()
{
  if [ ! -e /opt ]
  then
    echo "Did not find a /opt directory... creating it."
    echo $LINE
    SUDO_CMD mkdir /opt || error_exit
  fi
}


cleanup()
{
  $CLEANUP || return
  echo -n "Cleaning up working directory: ${WRKDIR} ... "
  rm -rf "$WRKDIR"
  echo "done"
}

##########################
# Main stuff starts here #
##########################
parse_commandline_args $@
first_of_all
install_required_packages ${META_DEPENDS[@]} # install packages required to run this utility

# Check for existence of a /opt directory, and create it if it doesn't exist.
check_for_opt_directory

clone

# Figure out what version number to use for the debian packages
bran_new_calculate_version_num

if $BUILD_X11RDP
then
  echo " *** Will remove the contents of ${X11RDPBASE} and ${WRKDIR}/xrdp-${XRDP_VERSION} ***"
  echo
fi

make_X11rdp_env

calc_cpu_cores # find out how many cores we have to play with, and if >1, set a possible make command

install_required_packages ${XRDP_BUILD_DEPENDS[@]} ${X11RDP_BUILD_DEPENDS[@]} ${XORGXRDP_BUILD_DEPENDS[@]}

download_compile

cleanup
install_generated_packages
clean_exit
