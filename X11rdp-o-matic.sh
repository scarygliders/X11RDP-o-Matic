#!/bin/bash

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

LINE="----------------------------------------------------------------------"
# Use the canonical git repo by default
XRDPGIT=https://github.com/neutrinolabs/xrdp.git
# Use the master branch by default
XRDPBRANCH=master

# Get list of available branches from remote git repository
get_branches()
{
  echo $LINE
  echo "Obtaining list of available branches..."
  echo $LINE
  BRANCHES=`git ls-remote --heads "$XRDPGIT" | cut -f2 | cut -d "/" -f 3`
  echo $BRANCHES
  echo $LINE
}

# If first switch = --help, display the help/usage message then exit.
if [[ $1 = "--help" ]]
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

###########################################################
# Before doing anything else, check if we're running with #
# priveleges, because from here onwards we need to be.    #
###########################################################
clear
id=`id -u`
if [ $id -ne 0 ]
	then
		clear
		echo "You tried running the Scarygliders X11rdp-O-Matic installation script as a non-priveleged user. Please run as root."
		exit 1
fi

# Install dialog if it's not already installed...
if [ ! -e /usr/bin/dialog ]
then
    echo "Installing the dialog package..."
    apt-get -y install dialog
fi

# Install lsb_release if it's not already installed...
if [ ! -e /usr/bin/lsb_release ]
then
  echo "Installing the lsb_release package..."
  apt-get -y install lsb-release
fi

#################################################################
# Initialise variables and parse any command line switches here #
#################################################################

# set LANG so that dpkg etc. return the expected responses so the script is
# guaranteed to work under different locales
export LANG="C"

# this is the release number for the Debian packages
RELEASE=1

TMPFILE=/tmp/xrdpver
X11DIR=/opt/X11rdp

ARCH=$( dpkg --print-architecture )

# Would have used /tmp for this, but some distros I tried mount /tmp as tmpfs
# and filled up.
WORKINGDIR=`pwd`
CONFIGUREFLAGS=(--prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-fuse)

# Declare a list of packages required to download sources/compile them...
REQUIREDPACKAGES=(build-essential checkinstall automake automake1.9 git
git-core libssl-dev libpam0g-dev zlib1g-dev libtool libtool-bin libx11-dev libxfixes-dev
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

DIST=`lsb_release -d -s`

# Check for running on supported/tested Distros...
SUPPORTED=0
while read i
do
  if [ "$DIST" = "$i" ]
  then
    SUPPORTED=1
    break
  fi
done < SupportedDistros.txt

INTERACTIVE=1	# Interactive by default.
PARALLELMAKE=1	# Utilise all available CPU's for compilation by default.
CLEANUP=0	# Keep the x11rdp and xrdp sources by default - to remove
		# requires --cleanup command line switch
INSTFLAG=1	# Install xrdp and x11rdp on this system
X11RDP=1	# Build and package x11rdp
BLEED=0		# Not bleeding-edge unless specified
TURBOJPEG=0     # Turbo JPEG not selected by default

# Parse the command line for any arguments
while [[ $# -gt 0 ]]
do
case "$1" in
  --justdoit)
    INTERACTIVE=0	# Don't bother with fancy schmancy dialogs, just go
			# through and do everything!
			# Note this will override even interactive Text Mode
    echo "Okay, will just do the install from start to finish with no user interaction..."
    echo $LINE
    ;;
    --branch)
    get_branches
    ok=0
    for check in ${BRANCHES[@]}
    do
      if [[ $check = $2 ]]
      then
	ok=1
      fi
    done
    if [[ $ok == 0 ]]
    then
      echo "**** Error detected in branch selection. Argument after --branch was : $2 ."
      echo "**** Available branches : "$BRANCHES
      exit 1
    fi
    XRDPBRANCH="$2"
    echo "Using branch ==>> $2 <<=="
    if [[ $XRDPBRANCH = "devel" ]]
    then
      echo "Note : using the bleeding-edge version may result in problems :)"
      BLEED=1
    fi
    echo $LINE
    shift
    ;;
    --nocpuoptimize)
      PARALLELMAKE=0
      echo "Will not utilize additional CPU's for compilation..."
      echo $LINE
    ;;
    --cleanup)
      CLEANUP=1
      echo "Will remove the xrdp and x11rdp sources in the working directory after compilation/installation..."
      echo $LINE
    ;;
    --noinstall)
      INSTFLAG=0
      echo "Will not install anything on the system but will build the packages"
      echo $LINE
    ;;
    --nox11rdp)
      X11RDP=0
      echo "Will not build and package x11rdp"
      echo $LINE
    ;;
    --withjpeg)
      CONFIGUREFLAGS+=(--enable-jpeg)
      REQUIREDPACKAGES+=(libjpeg8-dev)
    ;;
    --withturbojpeg)
      CONFIGUREFLAGS+=(--enable-tjpeg)
      if [[ $XRDPBRANCH = "v0.8" ]] # branch v0.8 has a hard-coded requirement for libjpeg-turbo to be in /opt
      then
	REQUIREDPACKAGES+=(nasm curl) # Need these for downloading and compiling libjpeg-turbo, later.
      else
	REQUIREDPACKAGES+=(libturbojpeg1 libturbojpeg1-dev) # The distro packages suffice for 0.9 onwards.
      fi
      TURBOJPEG=1
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

let "HEIGHT = $LINES - 3"
let "WIDTH = $COLUMNS - 8"

echo "Using the following xrdp configuration : "$CONFIGUREFLAGS
echo $LINE

#############################################
# Common function declarations begin here...#
#############################################

# Display a message box
info_window()
{
  dialog --backtitle "$backtitle" --title "$title" --msgbox "$dialogtext" 0 0
}

ask_question()
{
  dialog --backtitle "$backtitle" --title "$questiontitle" --yesno "$dialogtext" 0 0
  Answer=$?
}

apt_update_interactive()
{
  apt-get update | dialog --progressbox "Updating package databases..." 30 100
}

# Installs a package
install_package_interactive()
{
  debconf-apt-progress --dlwaypoint 50 -- apt-get -y install "$PkgName"
  sleep 1 # Prevent possible dpkg race condition (had that with Xubuntu 12.04 for some reason)
}

download_xrdp_interactive()
{
  git clone --depth 1 "$XRDPGIT" -b "$XRDPBRANCH" 2>&1 | dialog  --progressbox "Downloading xrdp source..." 30 100
}

download_xrdp_noninteractive()
{
  echo "Downloading xrdp source from the GIT repository..."
  git clone --depth 1 "$XRDPGIT" -b "$XRDPBRANCH"
}

compile_X11rdp_interactive()
{
  cd "$WORKINGDIR/xrdp/xorg/X11R7.6/"
  (sh buildx.sh "$X11DIR") 2>&1 | dialog  --progressbox "Compiling and installing X11rdp. This will take a while...." 30 100
}

compile_X11rdp_noninteractive()
{
  cd "$WORKINGDIR/xrdp/xorg/X11R7.6/"
  sh buildx.sh "$X11DIR"
  RC=$?
  if [ $RC -ne 0 ]; then
    echo "error building X11rdp"
    exit $RC
 fi
}

package_X11rdp_noninteractive()
{
  PKGDEST="$WORKINGDIR/packages/x11rdp"

  if [ ! -e "$PKGDEST" ]; then
    mkdir -p "$PKGDEST"
  fi

  if [ $BLEED == 1 ]
    then
        cd "$WORKINGDIR/xrdp/xorg/debuild"
        ./debX11rdp.sh "$VERSION" "$RELEASE" "$X11DIR" "$PKGDEST"
    else
        mkdir -p "$WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN"
        cp "$WORKINGDIR/control" "$WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN"
        cp -a "$WORKINGDIR/x11rdp_postinst" "$WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN/postinst"
        cd "$WORKINGDIR/xrdp/xorg/debuild"
        PACKDIR=x11rdp-files
        DESTDIR="$PACKDIR/opt"
        NAME=x11rdp
        sed -i -e "s/DUMMYVERINFO/$VERSION-$RELEASE/" "$PACKDIR/DEBIAN/control"
        sed -i -e "s/DUMMYARCHINFO/$ARCH/" "$PACKDIR/DEBIAN/control"
        # need a different delimiter, since it has a path
        sed -i -e "s,DUMMYDIRINFO,$X11DIR," "$PACKDIR/DEBIAN/postinst"
        mkdir -p "$DESTDIR"
        cp -Rf "$X11DIR" "$DESTDIR"
        dpkg-deb --build "$PACKDIR" "$PKGDEST/${NAME}_$VERSION-${RELEASE}_${ARCH}.deb"
        XORGPKGNAME="${NAME}_$VERSION-${RELEASE}_${ARCH}.deb"
        # revert to initial state
        rm -rf "$DESTDIR"
        sed -i -e "s/$VERSION-$RELEASE/DUMMYVERINFO/" "$PACKDIR/DEBIAN/control"
        sed -i -e "s/$ARCH/DUMMYARCHINFO/" "$PACKDIR/DEBIAN/control"
        # need a different delimiter, since it has a path
        sed -i -e "s,$X11DIR,DUMMYDIRINFO," "$PACKDIR/DEBIAN/postinst"
  fi
}

package_X11rdp_interactive()
{
  PKGDEST="$WORKINGDIR/packages/x11rdp"

  if [ ! -e "$PKGDEST" ]
  then
    mkdir -p "$PKGDEST"
  fi

  if [ $BLEED == 1 ]
  then
    cd "$WORKINGDIR/xrdp/xorg/debuild"
    ./debX11rdp.sh "$VERSION" "$RELEASE" "$X11DIR" "$PKGDEST"
  else
    ( mkdir -p "$WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN"
      cp "$WORKINGDIR/control" "$WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN"
      cp -a "$WORKINGDIR/x11rdp_postinst" "$WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN"
      cd "$WORKINGDIR/xrdp/xorg/debuild"
      PACKDIR=x11rdp-files
      DESTDIR="$PACKDIR/opt"
      NAME=x11rdp
      sed -i -e  "s/DUMMYVERINFO/$VERSION-$RELEASE/"  "$PACKDIR/DEBIAN/control"
      sed -i -e  "s/DUMMYARCHINFO/$ARCH/"  "$PACKDIR/DEBIAN/control"
      # need a different delimiter, since it has a path
      sed -i -e  "s,DUMMYDIRINFO,$X11DIR,"  "$PACKDIR/DEBIAN/postinst"
      mkdir -p "$DESTDIR"
      cp -Rf "$X11DIR" "$DESTDIR"
      dpkg-deb --build "$PACKDIR" "$PKGDEST/${NAME}_$VERSION-${RELEASE}_${ARCH}.deb"
      XORGPKGNAME="${NAME}_$VERSION-${RELEASE}_${ARCH}.deb"
      # revert to initial state
      rm -rf "$DESTDIR"
      sed -i -e "s/$VERSION-$RELEASE/DUMMYVERINFO/" "$PACKDIR/DEBIAN/control"
      sed -i -e "s/$ARCH/DUMMYARCHINFO/" "$PACKDIR/DEBIAN/control"
      # need a different delimiter, since it has a path
      sed -i -e "s,$X11DIR,DUMMYDIRINFO," "$PACKDIR/DEBIAN/postinst" ) 2>&1 | dialog --progressbox "Making X11rdp Debian Package..." 30 100
  fi
}

# Interactively compile & package xrdp using dh-make...
compile_xrdp_interactive()
{
  if [ ! -e "$WORKINGDIR/packages/xrdp" ]
  then
    mkdir -p "$WORKINGDIR/packages/xrdp"
  fi

  # Step 1: Run the bootstrap and configure scripts
  cd "$WORKINGDIR/xrdp"
  ( ./bootstrap && ./configure "$CONFIGUREFLAGS[@]}" ) 2>&1 | dialog  --progressbox "Preparing xrdp source to make a Debian package..." 50 100

  #Step 2 : Rename xrdp dir to xrdp-$VERSION for dh-make to work on...
  cd ..
  mv xrdp "xrdp-$VERSION"
  cd "xrdp-$VERSION"

  #Step 3 : Use dh-make to create the debian directory package template...
  ( echo | dh_make --single --native ) 2>&1 | dialog  --progressbox "Preparing xrdp source to make a Debian package..." 50 100

  #Step 4 : edit/configure the debian directory...
  cd debian
  rm *.ex *.EX # remove the example templates
  rm README.Debian
  rm README.source
  cp ../COPYING copyright # use the xrdp copyright file
  cp ../readme.txt README # use the xrdp readme.txt as the README file
  cp "$WORKINGDIR/xrdp_postinst" postinst # postinst to create xrdp init.d defaults
  cp "$WORKINGDIR/xrdp_control" control # use a generic control file
  cp "$WORKINGDIR/xrdp_prerm" prerm # pre-removal script
  cp "$WORKINGDIR/xrdp_docs" docs # use xrdp docs list

  #Step 5 : run dpkg-buildpackage to compile xrdp and build a package...
  cd ..
  ( dpkg-buildpackage -uc -us -tc -rfakeroot ) 2>&1 | dialog  --progressbox "Building xrdp source and packaging..." 50 100
  cd "$WORKINGDIR"
  mv xrdp*.deb "$WORKINGDIR/packages/xrdp/"
}

# Package xrdp using dh-make...
compile_xrdp_noninteractive()
{
  echo $LINE
  echo "Preparing xrdp source to make a Debian package..."
  echo $LINE

  if [ ! -e "$WORKINGDIR/packages/xrdp" ]
  then
    mkdir -p "$WORKINGDIR/packages/xrdp"
  fi

  # Step 1: Run the bootstrap and configure scripts
  cd "$WORKINGDIR/xrdp"
  ./bootstrap && ./configure "${CONFIGUREFLAGS[@]}"

  #Step 2 : Rename xrdp dir to xrdp-$VERSION for dh-make to work on...
  cd ..
  mv xrdp "xrdp-$VERSION"
  cd "xrdp-$VERSION"

  #Step 3 : Use dh-make to create the debian directory package template...
  echo | dh_make --single --native

  #Step 4 : edit/configure the debian directory...
  cd debian
  rm *.ex *.EX # remove the example templates
  rm README.Debian
  rm README.source
  cp ../COPYING copyright # use the xrdp copyright file
  cp ../readme.txt README # use the xrdp readme.txt as the README file
  cp "$WORKINGDIR/xrdp_postinst" postinst # postinst to create xrdp init.d defaults
  cp "$WORKINGDIR/xrdp_control" control # use a generic control file
  cp "$WORKINGDIR/xrdp_prerm" prerm # pre-removal script
  cp "$WORKINGDIR/xrdp_docs" docs # use xrdp docs list

  #Step 5 : run dpkg-buildpackage to compile xrdp and build a package...
  echo $LINE
  echo "Preparation complete. Building and packaging xrdp..."
  echo $LINE
  cd ..
  dpkg-buildpackage -uc -us -tc -rfakeroot
  cd "$WORKINGDIR"
  mv xrdp*.deb "$WORKINGDIR/packages/xrdp/"
}

remove_x11rdp_packages()
{
  (apt-get remove --purge x11rdp-*) 2>&1 | dialog --progressbox "Completely removing previously installed x11rdp packages..." 30 100
}

update_repositories()
{
  if [ "$INTERACTIVE" == "1" ]
  then
    welcome_message
    apt_update_interactive
  else
    echo "running apt-get update"
    apt-get update  >& /dev/null
  fi
}

# Interrogates dpkg to find out the status of a given package name...
check_package()
{
  DpkgStatus=`dpkg-query -s "$PkgName" 2>&1`
  case "$DpkgStatus" in
    *"is not installed and no info"*)
      PkgStatus=0
      # "Not installed."
    ;;
    *"deinstall ok config-files"*)
      PkgStatus=1
      # "Deinstalled, config files are still on system."
    ;;
    *"install ok installed"*)
      PkgStatus=2
      # "Installed."
    ;;
  esac
}

# Install or re-install package and give a relatively nice-ish message whilst doing so (if interactive)
install_package()
{
  if [ "$INTERACTIVE" == "1" ]
  then
    install_package_interactive
  else
    apt-get -y install "$PkgName"
  fi
}

# Check for necessary packages and install if necessary...
install_required_packages()
{
  for PkgName in "${REQUIREDPACKAGES[@]}"
  do
    check_package
    if [[ "$PkgStatus" == "0"  ||  $PkgStatus == "1" ]]
    then
      install_package
    fi
  done
}

calc_cpu_cores()
{
  Cores=`nproc`
  if [ $Cores -gt 1 ]
  then
    let "MakesystemWorkHarder = $Cores + 1"
    makeCommand="make -j $MakesystemWorkHarder"
  else
    PARALLELMAKE=0
  fi
}

cpu_cores_interactive()
{
  # See how many cpu cores we have to play with - we can speed up compilation if we have more cores ;)
  if [[ ! -e $WORKINGDIR/PARALLELMAKE && PARALLELMAKE = 1 ]] # No need to perform this if for some reason we've been here before...
  then
    if [ "$PARALLELMAKE" == "1" ]
    then
      dialogtext="Good news!\n\nYou can speed up the compilation because there are $Cores CPU cores available to this system.\n\nI can patch the X11rdp build script for you, to utilize the additional CPU cores.\nWould you like me to do this for you?\n\n(Answering Yes will add the \"-j [#cores+1]\" switch to the make command in the build script.\n\nIn this case it will be changed to \"$makeCommand\")."
      ask_question
      Question=$?
      case "$Question" in
	"0") # Yes please warm up my computer even more! ;)
	  # edit the buildx.sh patch file ;)
	  sed -i -e "s/make -j 1/$makeCommand/g" "$WORKINGDIR/buildx"_patch.diff
	  # create a file flag to say we've already done this
	  touch "$WORKINGDIR/PARALLELMAKE"
	  dialogtext="Ok, the optimization has been made.\n\nLooks like your system is going to be working hard soon ;)\n\nClick OK to proceed with the compilation."
	  info_window
	;;
	"1") # No thanks, I like waiting ;)
	  dialogtext="Ok, I will not change the build script as suggested.\n\nIt will take longer to compile though :)\n\nPress OK to proceed with the compilation..."
	  info_window
	;;
      esac
    fi
  fi
}

cpu_cores_noninteractive()
{
  if [ ! -e $WORKINGDIR/PARALLELMAKE ] # No need to perform this if for some reason we've been here before...
  then
    if [ "$PARALLELMAKE" == "1" ]
    then
      sed -i -e "s/make -j 1/$makeCommand/g" "$WORKINGDIR/buildx_patch.diff"
      touch "$WORKINGDIR/PARALLELMAKE"
    fi
  fi
}

welcome_message()
{
  case "$SUPPORTED" in
    "1")
      dialogtext="Welcome to the ScaryGliders X11rdp-O-Matic installation script.\n\nThe detected distribution is : $DIST.\n\nThis utility has been tested on this distribution.\n\nClick OK to continue..."
      info_window
    ;;
    "0")
      dialogtext=" Welcome to the ScaryGliders X11rdp-O-Matic installation script.\n\nThe detected distribution is : $DIST .\n\nUnfortunately, no testing has been done for running this utility on this distribution.\n\nIf this is a Debian-based distro, you can try running it. It might work, it might not.\n\nIf the utility does work on this distribution, please let the author know!\n\nClick OK to continue..."
      info_window
      ;;
  esac
}


# Create a useful version number for creating Debian packages.
# Worked out from the chosen branch.
calculate_version_num()
{
  README="https://raw.github.com/neutrinolabs/xrdp/$XRDPBRANCH/readme.txt"
  wget --no-check-certificate -O "$TMPFILE" "$README" >& /dev/null
  VERSION=$(grep xrdp "$TMPFILE" | head -1 | cut -d " " -f2)
  rm -f "$TMPFILE"
  if [[ $( echo $XRDPBRANCH | cut -c 1 ) != "v" ]]
  then
    VERSION="$VERSION+$XRDPBRANCH"
  fi
  echo "Debian package version number will be : $VERSION"
  echo $LINE
}

# Make a directory, to which the X11rdp build system will
# place all the built binaries and files.
make_X11rdp_env()
{
  if [ -e $X11DIR ] && [ $X11RDP -eq 1 ]
  then
    rm -rf "$X11DIR"
    mkdir -p "$X11DIR"
  fi

  if [ -e $WORKINGDIR/xrdp ]
  then
    rm -rf "$WORKINGDIR/xrdp"
  fi
}

# Alter xrdp source code Makefile.am so the PID file is now in /var/run/xrdp/
# Also patch rdp Makefile to tell Ubuntu linker to include GL symbols - pesky Ubuntu...
alter_xrdp_source()
{
  cd "$WORKINGDIR/xrdp"
  for file in `rgrep "localstatedir\}" . | cut -d":" -f1`
  do
    sed 's/localstatedir\}\/run/localstatedir\}\/run\/xrdp/' < "$file" > "$file.new"
    rm "$file"
    mv "$file.new" "$file"
  done
  cd "$WORKINGDIR"
  # Patch Jay's buildx.sh.
  # This will patch the make command for parallel makes if that was requested,
  # which should speed up compilation. It will make a backup copy of the original buildx.sh.
  if [ "$PARALLELMAKE" == "1" ]
  then
  	patch -b -d "$WORKINGDIR/xrdp/xorg/X11R7.6" buildx.sh < "$WORKINGDIR/buildx_patch.diff"
  fi

  # Patch rdp Makefile
  patch -b -d "$WORKINGDIR/xrdp/xorg/X11R7.6/rdp" Makefile < "$WORKINGDIR/rdp_Makefile.patch"

  # Patch v0.7 buildx.sh, as the file download location for Mesa has changed...
  if [[ $XRDPBRANCH = "v0.7" ]] # branch v0.7 has a moved libmesa
  then
      echo "Patching mesa download location..."
      patch -b -d "$WORKINGDIR/xrdp/xorg/X11R7.6" buildx.sh < "$WORKINGDIR/mesa.patch"
  fi
}

# make the /usr/bin/X11rdp symbolic link if it doesn't exist...
make_X11rdp_symbolic_link()
{
  if [ ! -e /usr/bin/X11rdp ]
  then
    if [ -e $X11DIR/bin/X11rdp ]
    then
      ln -s "$X11DIR/bin/X11rdp" /usr/bin/X11rdp
    else
      clear
      echo "There was a problem... the /opt/X11rdp/bin/X11rdp binary could not be found. Did the compilation complete?"
      echo "Stopped. Please investigate what went wrong."
      exit
    fi
  fi
}

# make the doc directory if it doesn't exist...
make_doc_directory()
{
  if [ ! -e /usr/share/doc/xrdp ]
  then
    mkdir /usr/share/doc/xrdp
  fi
}

install_generated_packages()
{
  ERRORFOUND=0

  if [ $X11RDP == "1" ]
  then
    FILES=("$WORKINGDIR"/packages/Xorg/X11rdp*.deb)
    if [ ${#FILES[@]} -gt 0 ]
    then
      remove_currently_installed_X11rdp
      dpkg -i "$WORKINGDIR/packages/Xorg/*.deb"
    else
      ERRORFOUND=1
      echo "We were supposed to have built X11rdp but I couldn't find a package file."
      echo "Please check that X11rdp built correctly. It probably didn't."
    fi
  fi
  FILES=("$WORKINGDIR"/packages/xrdp/xrdp*.deb)
  if [ ${#FILES[@]} -gt 0 ]
  then
    remove_currently_installed_xrdp
    dpkg -i "$WORKINGDIR"/packages/xrdp/xrdp*.deb
  else
    echo "I couldn't find an xrdp Debian package to install."
    echo "Please check that xrdp compiled correctly. It probably didn't."
    ERRORFOUND=1
  fi
  if [ $ERRORFOUND == "1" ]
  then
    exit
  fi
}

control_c()
{
  clear
  cd "$WORKINGDIR"
  echo "*** CTRL-C was pressed - aborted ***"
  exit
}

download_compile_interactively()
{
  download_xrdp_interactive
  if [[ "$PARALLELMAKE" == "1"  && "$Cores" -gt "1" ]] # Ask about parallel make if requested AND if you have more than 1 CPU core...
  then
    cpu_cores_interactive
  fi
  alter_xrdp_source
  if  [ "$X11RDP" == "1" ]; then
    compile_X11rdp_interactive
    package_X11rdp_interactive
    make_X11rdp_symbolic_link
  fi
  compile_xrdp_interactive
}

download_compile_noninteractively()
{
  download_xrdp_noninteractive
  if [ "$PARALLELMAKE" == "1" ]
  then
    cpu_cores_noninteractive
  fi

  alter_xrdp_source # Patches the downloaded source

  if  [ "$X11RDP" == "1" ]
  then
    compile_X11rdp_noninteractive
    package_X11rdp_noninteractive
    make_X11rdp_symbolic_link
  fi

  # New method...
  # Compiles & packages using dh_make and dpkg-buildpackage
  compile_xrdp_noninteractive
}

remove_existing_generated_packages()
{
  echo "Checking for previously generated packages..."
  echo $LINE
  ls "$WORKINGDIR"/packages/xrdp/X11rdp*.deb >/dev/null 2>&1
  if [ $? == 0 ]
  then
    echo "Removing previously generated Debian X11rdp package file(s)."
    echo $LINE
    rm "$WORKINGDIR"/packages/Xorg/*.deb
  fi

  ls "$WORKINGDIR"/packages/xrdp/xrdp*.deb >/dev/null 2>&1
  if [ $? == 0 ]
  then
    echo "Removing previously generated Debian xrdp package file(s)."
    echo $LINE
    rm "$WORKINGDIR"/packages/xrdp/*.deb
  fi
}

remove_currently_installed_xrdp()
{
  PkgName="xrdp"
  check_package
  if [ $PkgStatus == "2" ]
  then
    echo "Removing the currently installed xrdp package."
    echo $LINE
    apt-get -y remove xrdp
  fi
}

remove_currently_installed_X11rdp()
{
  PkgName="X11rdp"
  check_package
  if [ $PkgStatus == "2" ]
  then
    echo "Removing the currently installed X11rdp package."
    echo $LINE
    apt-get -y remove X11rdp
  fi
}

check_for_opt_directory()
{
  if [[ ! -e /opt ]]
  then
    echo "Did not find a /opt directory... creating it."
    echo $LINE
    mkdir /opt
  fi
}


download_and_extract_libturbojpeg()
{
  cd "$WORKINGDIR"
  echo "TurboJPEG library needs to be built and installed to /opt... downloading and extracting source..."
  sleep 2
  curl -O -J -L http://sourceforge.net/projects/libjpeg-turbo/files/1.3.1/libjpeg-turbo-1.3.1.tar.gz/download#
  tar xf libjpeg-turbo-1.3.1.tar.gz
}

build_turbojpeg()
{
  cd "$WORKINGDIR/libjpeg-turbo-1.3.1"
  echo "Configuring Turbo JPEG..."
  ./configure
  echo "Building TurboJPEG..."
  make
  echo $LINE
  echo "Installing TurboJPEG to default /opt directory..."
  make install
  echo $LINE
  if [[ -e /opt/libjpeg-turbo/lib64 ]] # Make symbolic link to libjpeg-turbo's lib64 if it doesn't already exist
  then
    if [[ ! -e /opt/libjpeg-turbo/lib ]]
    then
      echo "Making symbolic link to /opt/libjpeg-turbo/lib64..."
      ln -s /opt/libjpeg-turbo/lib64 /opt/libjpeg-turbo/lib
    fi
  fi

  if [[ -e /opt/libjpeg-turbo/lib32 ]] # Make symbolic link to libjpeg-turbo's lib32 if it doesn't already exist
  then
    if [[ ! -e /opt/libjpeg-turbo/lib ]]
    then
      echo "Making symbolic link to /opt/libjpeg-turbo/lib32..."
      ln -s /opt/libjpeg-turbo/lib32 /opt/libjpeg-turbo/lib
    fi
  fi
  echo "Continuing with building xrdp..."
  echo $LINE
  sleep 2
  cd "$WORKINGDIR"
}


# if v0.8 selected and --withturbojpeg also selected, we need to build turbojpeg
check_v08_and_turbojpeg()
{
  if [[ $XRDPBRANCH = "v0.8" ]]
  then
    if [ "$TURBOJPEG" == "1" ]
    then
      echo $LINE
      echo "v0.8 branch selected and --withturbojpeg. Checking for existing lib in /opt ..."
      echo $LINE
      if [[ ! -e /opt/libjpeg-turbo ]] # If the library hasn't already been downloaded & built, then do so
      then                             # Otherwise, assume it has already been built and do nothing more.
	download_and_extract_libturbojpeg
	build_turbojpeg
      else
	echo "The necessary turbojpeg lib already exists in /opt so no need to build it again. Waiting 5 seconds..."
	echo $LINE
	sleep 5
      fi
    fi
  fi
}

cleanup()
{
  rm -rf "$WORKINGDIR/xrdp-$VERSION"
}

##########################
# Main stuff starts here #
##########################

# Check for existence of a /opt directory, and create it if it doesn't exist.
check_for_opt_directory

# Figure out what version number to use for the debian packages
calculate_version_num

# trap keyboard interrupt (control-c)
trap control_c SIGINT

if [ "$X11RDP" == "1" ]; then
  echo " *** Will remove the contents of $X11DIR and $WORKINGDIR/xrdp-$VERSION ***"
  echo
fi

if [ "$INTERACTIVE" == "1" ]
then
  echo "Press ENTER to continue or CTRL-C to abort"
  read DUMMY
else
  echo "Waiting 5 seconds. Press CTRL+C to abort"
  sleep 5
fi

if [ "$INSTFLAG" == "0" ]; then
  INSTOPT="no"
else
  INSTOPT="yes"
fi

make_X11rdp_env

calc_cpu_cores # find out how many cores we have to play with, and if >1, set a possible make command

update_repositories # perform an apt update to make sure we have a current list of available packages

install_required_packages # install any packages required for xrdp/X11rdp (and libjpeg-turbo if needed) compilation

remove_existing_generated_packages # Yes my function names become ever more ridiculously long :D

check_v08_and_turbojpeg # v0.8 branch needs libturbojpeg to be in /opt

if [ "$INTERACTIVE" == "1" ]
then
  download_compile_interactively
else
  download_compile_noninteractively
fi

if [ "$CLEANUP" == "1" ] # Also remove the xrdp source tree if asked to.
then
  cleanup
fi

if [ "$INSTFLAG" == "0" ] # If not installing on this system...
then
  # this is stupid but some Makefiles from X11rdp don't have an uninstall target (ex: Python!)
  # ... so instead of not installing X11rdp we remove it in the end
  if  [ "$X11RDP" == "1" ] # If we compiled X11rdp then remove the generated X11rdp files (from /opt)
  then
    rm -rf "$X11DIR"
  fi

  echo $LINE
  echo "Will exit now, since we are not installing on this system..."
  echo "Packages have been placed under their respective directories in the"
  echo "packages directory."
  echo $LINE
  exit

 else # Install the packages on the system
  # make_doc_directory # <--- Probably not needed anymore since the dh_make
                       # method includes the doc directory ;)
  # stop xrdp if running
  /etc/init.d/xrdp stop

  install_generated_packages

  if [ $INTERACTIVE == 1 ]
  then
    dialogtext="X11rdp and xrdp should now be fully installed, configured, and running on this system.\n
    One last thing to do now is to configure which desktop will be presented to the user after they log in via RDP.\n
    You may not have to do this - test by logging into xrdp now.\n
    Or use the RDPsesconfig.sh utility to configure a session's desktop."
    info_window
  else
    echo $LINE
    echo "X11rdp and xrdp should now be fully installed, configured, and running on this system."
    echo "One last thing to do now is to configure which desktop will be presented to the user after they log in via RDP."
    echo "You may not have to do this - test by logging into xrdp now."
    echo "Or use the RDPsesconfig.sh utility to configure a session's desktop."
    echo $LINE
  fi
fi
