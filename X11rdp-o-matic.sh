#!/bin/bash
# vim:ts=2:sw=2:sts=0:number:expandtab
set -e

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
# working directories
WRKDIR=$(mktemp --directory --suffix .X11RDP-o-Matic)
BASEDIR=$(dirname $(readlink -f $0))
PKGDIR=${BASEDIR}/packages
PATCHDIR=${BASEDIR}/patch
# log dir
APT_LOG=${WRKDIR}/apt.log
BUILD_LOG=${WRKDIR}/build.log
SUDO_LOG=${WRKDIR}/sudo.log

# packages to run this utility
META_DEPENDS=(lsb-release rsync)

# check if the system is using systemd or not
[ -z "$(pidof systemd)" ] && \
  USING_SYSTEMD=false || \
  USING_SYSTEMD=true

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
  #[ -f .PID ] && [ "$(cat .PID)" = $$ ] && rm -f .PID
  exit 1
}

user_interrupt_exit()
{
  echo_stderr; echo_stderr
  echo_stderr "Script stopped due to user interrupt, exitting..."
  cd "$BASEDIR"
  exit 1
}

# call like this: install_required_packages ${PACKAGES[@]}
install_required_packages()
{
  for f in $@
  do
    echo -n "Checking for ${f}... "
    check_package $f
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
check_package()
{
  # if not installed, the last command's exit code will be 1
  dpkg-query -W --showformat='${Status}\n' "$1" 2>/dev/null | grep -q -e "deinstall ok" -e "not installed" 
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
  --withjpeg         : build jpeg module
                       (uses Independent JPEG Group's JPEG runtime library)
  --withturbojpeg    : build turbo jpeg module
                       (As used by TigerVNC and other users of the past TurboJPEG library)
  --withsimplesound  : build the simple pulseaudio interface
  --withpulse        : build code to load pulse audio modules
  --withdebug        : build with debug enabled
  --withneutrino     : build the neutrinordp module
  --withkerberos     : build support for kerberos
  --withxrdpvr       : build the xrdpvr module
  --withnopam        : don't include PAM support
  --withpamuserpass  : build with pam userpass support
  --withfreerdp      : build the freerdp1 module
  "
  get_branches
  exit
fi

clear

install_required_packages ${META_DEPENDS[@]} # install packages required to run this utility

#################################################################
# Initialise variables and parse any command line switches here #
#################################################################

RELEASE=1 # release number for debian packages

TMPFILE=/tmp/xrdpver
X11RDPDEST=/opt/X11rdp

ARCH=$(dpkg --print-architecture)

# Would have used /tmp for this, but some distros I tried mount /tmp as tmpfs
# and filled up.
CONFIGUREFLAGS=(--prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-fuse)

# Declare a list of packages required to download sources/compile them...
REQUIREDPACKAGES=(build-essential checkinstall automake git
git-core libssl-dev libpam0g-dev zlib1g-dev libtool libx11-dev libxfixes-dev
pkg-config flex bison libxml2-dev intltool xsltproc xutils-dev python-libxml2
g++ xutils libfuse-dev wget libxrandr-dev libdrm-dev libpixman-1-dev
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
  REQUIREDPACKAGES+=(libtool-bin)

DIST=$(lsb_release -d -s)

PARALLELMAKE=true   # Utilise all available CPU's for compilation by default.
CLEANUP=false       # Keep the x11rdp and xrdp sources by default - to remove
                    # requires --cleanup command line switch
INSTALL_XRDP=true   # Install xrdp and x11rdp on this system
BUILD_XRDP=true     # Build and package x11rdp
BLEED=false         # Not bleeding-edge unless specified
USE_TURBOJPEG=false # Turbo JPEG not selected by default
GIT_USE_HTTPS=true  # Use firewall-friendry https:// instead of git:// to fetch git submodules

# Parse the command line for any arguments
while [ $# -gt 0 ]
do
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
    XRDPBRANCH="$2"
    echo "Using branch ==>> $2 <<=="
    if [ "$GH_BRANCH" = "devel" ]
    then
      echo "Note : using the bleeding-edge version may result in problems :)"
      BLEED=true
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
    INSTALL_XRDP=false
    echo "Will not install anything on the system but will build the packages"
    echo $LINE
    ;;
  --nox11rdp)
    BUILD_XRDP=false
    echo "Will not build and package x11rdp"
    echo $LINE
    ;;
  --withjpeg)
    CONFIGUREFLAGS+=(--enable-jpeg)
    REQUIREDPACKAGES+=(libjpeg8-dev)
    ;;
  --withturbojpeg)
    CONFIGUREFLAGS+=(--enable-tjpeg)
    if [[ $GH_BRANCH = "v0.8"* ]] # branch v0.8 has a hard-coded requirement for libjpeg-turbo to be in /opt
    then
      REQUIREDPACKAGES+=(nasm curl) # Need these for downloading and compiling libjpeg-turbo, later.
    else
      REQUIREDPACKAGES+=(libturbojpeg1 libturbojpeg1-dev) # The distro packages suffice for 0.9 onwards.
    fi
    USE_TURBOJPEG=true
    ;;
  --withsimplesound)
    CONFIGUREFLAGS+=(--enable-simplesound)
    REQUIREDPACKAGES+=(libpulse-dev)
    ;;
  --withpulse)
    CONFIGUREFLAGS+=(--enable-loadpulsemodules)
    REQUIREDPACKAGES+=(libpulse-dev)
    ;;
  --withdebug)
    CONFIGUREFLAGS+=(--enable-xrdpdebug)
    ;;
  --withneutrino)
    CONFIGUREFLAGS+=(--enable-neutrinordp)
    ;;
  --withkerberos)
    CONFIGUREFLAGS+=(--enable-kerberos)
    ;;
  --withxrdpvr)
    CONFIGUREFLAGS+=(--enable-xrdpvr)
    REQUIREDPACKAGES+=(libavcodec-dev libavformat-dev)
    ;;
  --withnopam)
    CONFIGUREFLAGS+=(--disable-pam)
    ;;
  --withpamuserpass)
    CONFIGUREFLAGS+=(--enable-pamuserpass)
    ;;
  --withfreerdp)
    CONFIGUREFLAGS+=(--enable-freerdp1)
    REQUIREDPACKAGES+=(libfreerdp-dev)
    ;;
esac
shift
done

echo "Using the following xrdp configuration : "$CONFIGUREFLAGS
echo $LINE

#############################################
# Common function declarations begin here...#
#############################################

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
  fi
  echo 'done'
}

compile_X11rdp_noninteractive()
{
  cd "$WRKDIR/xrdp/xorg/X11R7.6/"
  SUDO_CMD sh buildx.sh "$X11RDPDEST" || error_exit
}

package_X11rdp_noninteractive()
{
  PKGDEST="$PKGDIR/x11rdp"

  if [ ! -e "$PKGDEST" ]; then
    mkdir -p "$PKGDEST"
  fi

  if [ -f "$WRKDIR/xrdp/xorg/debuild/debX11rdp.sh" ]
  then
    # usually reach here
    cd "$WRKDIR/xrdp/xorg/debuild"
    ./debX11rdp.sh "$VERSION" "$RELEASE" "$X11RDPDEST" "$PKGDEST"
  else
    mkdir -p "$WRKDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN"
    cp "$BASEDIR/debian/x11rdp_control" "$WRKDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN/control"
    cp -a "$BASEDIR/debian/x11rdp_postinst" "$WRKDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN/postinst"
    cd "$WRKDIR/xrdp/xorg/debuild"
    PACKDIR=x11rdp-files
    DESTDIR="$PACKDIR/opt"
    NAME=x11rdp
    sed -i -e "s/DUMMYVERINFO/$VERSION-$RELEASE/" "$PACKDIR/DEBIAN/control"
    sed -i -e "s/DUMMYARCHINFO/$ARCH/" "$PACKDIR/DEBIAN/control"
    # need a different delimiter, since it has a path
    sed -i -e "s,DUMMYDIRINFO,$X11RDPDEST," "$PACKDIR/DEBIAN/postinst"
    mkdir -p "$DESTDIR"
    cp -Rf "$X11RDPDEST" "$DESTDIR"
    dpkg-deb --build "$PACKDIR" "$PKGDEST/${NAME}_$VERSION-${RELEASE}_${ARCH}.deb"
    XORGPKGNAME="${NAME}_$VERSION-${RELEASE}_${ARCH}.deb"
    # revert to initial state
    rm -rf "$DESTDIR"
    sed -i -e "s/$VERSION-$RELEASE/DUMMYVERINFO/" "$PACKDIR/DEBIAN/control"
    sed -i -e "s/$ARCH/DUMMYARCHINFO/" "$PACKDIR/DEBIAN/control"
    # need a different delimiter, since it has a path
    sed -i -e "s,$X11RDPDEST,DUMMYDIRINFO," "$PACKDIR/DEBIAN/postinst"
  fi
}

# Package xrdp using dh-make...
compile_xrdp_noninteractive()
{
  PKGDEST="$PKGDIR/xrdp"

  echo $LINE
  echo "Preparing xrdp source to make a Debian package..."
  echo $LINE

  if [ ! -e "$PKGDEST" ]; then
    mkdir -p "$PKGDEST"
  fi

  # Step 1: Link xrdp dir to xrdp-$VERSION for dh_make to work on...
  rsync -a --delete -- "${WRKDIR}/xrdp/" "${WRKDIR}/xrdp-${VERSION}"

  # Step 2: Run the bootstrap and configure scripts
  cd "$WRKDIR/xrdp-$VERSION"
  ./bootstrap && ./configure "${CONFIGUREFLAGS[@]}" || error_exit

  # Step 3 : Use dh-make to create the debian directory package template...
  dh_make_y --single --copyright apache --createorig

  # Step 4 : edit/configure the debian directory...
  cd debian
  rm *.ex *.EX # remove the example templates
  rm README.Debian
  rm README.source
  cp ../COPYING copyright # use the xrdp copyright file
  cp ../readme.txt README # use the xrdp readme.txt as the README file
  cp "$BASEDIR/debian/postinst" postinst # postinst to create xrdp init.d defaults
  cp "$BASEDIR/debian/control" control # use a generic control file
  cp "$BASEDIR/debian/prerm" prerm # pre-removal script
  cp "$BASEDIR/debian/docs" docs # use xrdp docs list

  # Step 5 : run dpkg-buildpackage to compile xrdp and build a package...
  echo $LINE
  echo "Preparation complete. Building and packaging xrdp..."
  echo $LINE
  cd ..
  dpkg-buildpackage -uc -us -tc -rfakeroot
  cd "$WRKDIR"
  mv xrdp*.deb "${PKGDIR}/xrdp/"
}

update_repositories()
{
    SUDO_CMD apt-get update >> $APT_LOG || error_exit
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

cpu_cores_noninteractive()
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

# Create a useful version number for creating Debian packages.
# Worked out from the chosen branch.
calculate_version_num()
{
  README="https://raw.github.com/${GH_ACCOUNT}/${GH_PROJECT}/${GH_BRANCH}/readme.txt"
  wget --no-check-certificate -O "$TMPFILE" "$README" >& /dev/null
  VERSION=$(grep xrdp "$TMPFILE" | head -1 | cut -d " " -f2)
  rm -f "$TMPFILE"
  if [ "${XRDPBRANCH#v}" = "$GH_BRANCH" ]
  then
    VERSION="$VERSION+$GH_BRANCH"
  fi
  echo "Debian package version number will be : $VERSION"
  echo $LINE
}

# Make a directory, to which the X11rdp build system will
# place all the built binaries and files.
make_X11rdp_env()
{
  if [ -e "$X11RDPDEST" -a "$X11RDPDEST" != "/" ] && $BUILD_XRDP
  then
    SUDO_CMD rm -rf "$X11RDPDEST" || error_exit
    SUDO_CMD mkdir -p "$X11RDPDEST" || error_exit
  fi

  if [ -e "$WRKDIR/xrdp" ]
  then
    rm -rf "$WRKDIR/xrdp"
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
    patch -b -d "$WRKDIR/xrdp/xorg/X11R7.6" buildx.sh < "$PATCHDIR/buildx_patch.diff"
  fi

  # Patch rdp Makefile
  patch -b -d "$WRKDIR/xrdp/xorg/X11R7.6/rdp" Makefile < "$PATCHDIR/rdp_Makefile.patch"

  # Patch v0.7 buildx.sh, as the file download location for Mesa has changed...
  if [[ $GH_BRANCH = "v0.7"* ]] # branch v0.7 has a moved libmesa
  then
      echo "Patching mesa download location..."
      patch -b -d "$WRKDIR/xrdp/xorg/X11R7.6" buildx.sh < "$PATCHDIR/mesa.patch"
  fi
}

# make the /usr/bin/X11rdp symbolic link if it doesn't exist...
make_X11rdp_symbolic_link()
{
  if [ ! -e /usr/bin/X11rdp ]
  then
    if [ -e "$X11RDPDEST/bin/X11rdp" ]
    then
      SUDO_CMD ln -s "$X11RDPDEST/bin/X11rdp" /usr/bin/X11rdp
    else
      clear
      echo "There was a problem... the /opt/X11rdp/bin/X11rdp binary could not be found. Did the compilation complete?"
      echo "Stopped. Please investigate what went wrong."
      exit
    fi
  fi
}

install_generated_packages()
{
  ERRORFOUND=0

  if $BUILD_XRDP
  then
    FILES=("$PKGDIR"/x11rdp/x11rdp*.deb)
    if [ ${#FILES[@]} -gt 0 ]
    then
      remove_currently_installed_X11rdp
      SUDO_CMD dpkg -i "$PKGDIR"/x11rdp/x11rdp*.deb
    else
      ERRORFOUND=1
      echo "We were supposed to have built X11rdp but I couldn't find a package file."
      echo "Please check that X11rdp built correctly. It probably didn't."
    fi
  fi
  FILES=("$PKGDIR"/xrdp/xrdp*.deb)
  if [ ${#FILES[@]} -gt 0 ]
  then
    remove_currently_installed_xrdp
    SUDO_CMD dpkg -i "$PKGDIR"/xrdp/xrdp*.deb
  else
    echo "I couldn't find an xrdp Debian package to install."
    echo "Please check that xrdp compiled correctly. It probably didn't."
    ERRORFOUND=1
  fi
  if [ $ERRORFOUND -eq 1 ]
  then
    exit
  fi
}



download_compile_noninteractively()
{
  clone
  if $PARALLELMAKE
  then
    cpu_cores_noninteractive
  fi

  alter_xrdp_source # Patches the downloaded source

  # New method...
  # Compiles & packages using dh_make and dpkg-buildpackage
  compile_xrdp_noninteractive

  if $BUILD_XRDP
  then
    compile_X11rdp_noninteractive
    package_X11rdp_noninteractive
    make_X11rdp_symbolic_link
  fi
}

remove_existing_generated_packages()
{
  echo "Checking for previously generated packages..."
  echo $LINE
  if ls "$PKGDIR"/xrdp/X11rdp*.deb >/dev/null 2>&1
  then
    echo "Removing previously generated Debian X11rdp package file(s)."
    echo $LINE
    rm "$PKGDIR"/Xorg/*.deb
  fi

  if ls "$PKGDIR"/xrdp/xrdp*.deb >/dev/null 2>&1
  then
    echo "Removing previously generated Debian xrdp package file(s)."
    echo $LINE
    rm "$PKGDIR"/xrdp/*.deb
  fi
}

remove_currently_installed_xrdp()
{
  check_package xrdp
  if [ $? -eq 0 ]
  then
    echo "Removing the currently installed xrdp package."
    echo $LINE
    SUDO_CMD apt-get -y remove xrdp || error_exit
  fi
}

remove_currently_installed_X11rdp()
{
  check_package x11rdp
  if [ $? -eq 0 ]
  then
    echo "Removing the currently installed X11rdp package."
    echo $LINE
    SUDO_CMD apt-get -y remove x11rdp || error_exit
  fi
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


download_and_extract_libturbojpeg()
{
  cd "$WRKDIR"
  echo "TurboJPEG library needs to be built and installed to /opt... downloading and extracting source..."
  [ -d libjpeg-turbo ] && return 0
  [ -s libjpeg-turbo-1.3.1.tar.gz ] ||
  curl -O -J -L http://sourceforge.net/projects/libjpeg-turbo/files/1.3.1/libjpeg-turbo-1.3.1.tar.gz/download#
  tar xf libjpeg-turbo-1.3.1.tar.gz
  ln -s libjpeg-turbo-1.3.1 libjpeg-turbo
}

build_turbojpeg()
{
  cd "$WRKDIR/libjpeg-turbo"
  echo "Configuring Turbo JPEG..."
  ./configure
  echo "Building TurboJPEG..."
  make
  echo $LINE
  echo "Installing TurboJPEG to default /opt directory..."
  make install
  echo $LINE
  if [ -e /opt/libjpeg-turbo/lib64 ] # Make symbolic link to libjpeg-turbo's lib64 if it doesn't already exist
  then
    if [ ! -e /opt/libjpeg-turbo/lib ]
    then
      echo "Making symbolic link to /opt/libjpeg-turbo/lib64..."
      ln -s /opt/libjpeg-turbo/lib64 /opt/libjpeg-turbo/lib
    fi
  fi

  if [ -e /opt/libjpeg-turbo/lib32 ] # Make symbolic link to libjpeg-turbo's lib32 if it doesn't already exist
  then
    if [ ! -e /opt/libjpeg-turbo/lib ]
    then
      echo "Making symbolic link to /opt/libjpeg-turbo/lib32..."
      ln -s /opt/libjpeg-turbo/lib32 /opt/libjpeg-turbo/lib
    fi
  fi
  echo "Continuing with building xrdp..."
  echo $LINE
  cd "$WRKDIR"
}

# if v0.8 selected and --withturbojpeg also selected, we need to build turbojpeg
check_v08_and_turbojpeg()
{
  if [[ "$GH_BRANCH" = "v0.8"* ]]
  then
    if $USE_TURBOJPEG
    then
      echo $LINE
      echo "v0.8 branch selected and --withturbojpeg. Checking for existing lib in /opt ..."
      echo $LINE
      if [ ! -e /opt/libjpeg-turbo ] # If the library hasn't already been downloaded & built, then do so
      then                             # Otherwise, assume it has already been built and do nothing more.
        download_and_extract_libturbojpeg
        build_turbojpeg
      else
        echo "The necessary turbojpeg lib already exists in /opt so no need to build it again. Waiting 5 seconds..."
        echo $LINE
      fi
    fi
  fi
}

cleanup()
{
  rm -rf "$WRKDIR/xrdp-$VERSION"
}

##########################
# Main stuff starts here #
##########################

# Check for existence of a /opt directory, and create it if it doesn't exist.
check_for_opt_directory

# Figure out what version number to use for the debian packages
calculate_version_num

if $BUILD_XRDP
then
  echo " *** Will remove the contents of $X11RDPDEST and $WRKDIR/xrdp-$VERSION ***"
  echo
fi

if ! $INSTALL_XRDP
then
  INSTOPT="no"
else
  INSTOPT="yes"
fi

make_X11rdp_env

calc_cpu_cores # find out how many cores we have to play with, and if >1, set a possible make command

update_repositories # perform an apt update to make sure we have a current list of available packages

install_required_packages ${REQUIREDPACKAGES[@]} # install any packages required for xrdp/X11rdp (and libjpeg-turbo if needed) compilation

remove_existing_generated_packages # Yes my function names become ever more ridiculously long :D

check_v08_and_turbojpeg # v0.8 branch needs libturbojpeg to be in /opt

download_compile_noninteractively

if $CLEANUP # Also remove the xrdp source tree if asked to.
then
  cleanup
fi

if ! $INSTALL_XRDP # If not installing on this system...
then
  # this is stupid but some Makefiles from X11rdp don't have an uninstall target (ex: Python!)
  # ... so instead of not installing X11rdp we remove it in the end
  if $BUILD_XRDP # If we compiled X11rdp then remove the generated X11rdp files (from /opt)
  then
    rm -rf "$X11RDPDEST"
  fi

  echo $LINE
  echo "Will exit now, since we are not installing on this system..."
  echo "Packages have been placed under their respective directories in the"
  echo "packages directory."
  echo $LINE
  exit

else # Install the packages on the system
  # stop xrdp if running
  if $USING_SYSTEMD
  then
    SUDO_CMD systemctl stop xrdp
  else
    SUDO_CMD service xrdp stop
  fi

  install_generated_packages

  echo $LINE
  echo "X11rdp and xrdp should now be fully installed, configured, and running on this system."
  echo "One last thing to do now is to configure which desktop will be presented to the user after they log in via RDP."
  echo "You may not have to do this - test by logging into xrdp now."
  echo "Or use the RDPsesconfig.sh utility to configure a session's desktop."
  echo $LINE
fi
