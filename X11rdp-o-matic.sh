#!/bin/bash

# Automatic Xrdp/X11rdp Compiler/Installer
# a.k.a. ScaryGliders X11rdp-O-Matic
#
# Version 3.04
#
# Version release date : 20140304
########################(yyyyMMDD)
#
# Will run on Debian-based systems only at the moment. RPM based distros perhaps some time in the future...
#
# Copyright (C) 2012-2014, Kevin Cave <kevin@scarygliders.net>
# With contributions from other kind people.
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
  BRANCHES=`git ls-remote --heads $XRDPGIT | cut -f2 | cut -d "/" -f 3`
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
  --branch <branch>  : use one of the available xrdp branches listed above...
                       Examples:
                       --branch v0.8    - use the 0.8 branch.
                       --branch master  - use the master branch. <-- Default if no --branch switch used.
                       --branch devel   - use the devel branch (Bleeding Edge - may not work properly!)
                       Branches beginning with "v" are stable releases.
                       The master branch changes when xrdp authors merge changes from the devel branch.
  --nocpuoptimize    : do not change X11rdp build script to utilize more than 1 of your CPU cores.
  --nocleanup        : do not remove X11rdp / xrdp source code after installation. (Default is to clean up).
  --noinstall        : do not install anything, just build the packages
  --nox11rdp         : only build xrdp, without the x11rdp backend
  --withjpeg         : include jpeg module
  --withsound        : include building of the simple pulseaudio interface
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
#################################################################
# Initialise variables and parse any command line switches here #
#################################################################

# set LANG so that dpkg etc. return the expected responses so the script is guaranteed to work under different locales
export LANG="C"

# this is the release number for the Debian packages
RELEASE=1

TMPFILE=/tmp/xrdpver
X11DIR=/opt/X11rdp
WORKINGDIR=`pwd` # Would have used /tmp for this, but some distros I tried mount /tmp as tmpfs, and filled up.
CONFIGUREFLAGS="--prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-fuse"

# Declare a list of packages required to download sources/compile them...
RequiredPackages=(build-essential checkinstall automake automake1.9 git git-core libssl-dev libpam0g-dev zlib1g-dev libtool libx11-dev libxfixes-dev pkg-config flex bison libxml2-dev intltool xsltproc xutils-dev python-libxml2 g++ xutils libfuse-dev wget libxrandr-dev)

Dist=`lsb_release -d -s`

# Check for running on supported/tested Distros...
supported=0
while read i
do
	if [ "$Dist" = "$i" ]
	then
		supported=1
		break
	fi
done < SupportedDistros.txt

INTERACTIVE=1	# Interactive by default.
PARALLELMAKE=1	# Utilise all available CPU's for compilation by default.
CLEANUP=1	# Cleanup the x11rdp and xrdp sources by default - to keep requires --nocleanup command line switch
INSTFLAG=1	# Install xrdp and x11rdp on this system
X11RDP=1	# Build and package x11rdp
BLEED=0		# Not bleeding-edge unless specified

# Parse the command line for any arguments
while [[ $# -gt 0 ]]
do
case "$1" in
  --justdoit)
    INTERACTIVE=0	# Don't bother with fancy schmancy dialogs, just go through and do everything!
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
    PARALLELMAKE=0	# Don't utilize additional CPU cores for compilation.
    echo "Will not utilize additional CPU's for compilation..."
    echo $LINE
    ;;
    --nocleanup)
    CLEANUP=0 	# Don't remove the xrdp and x11rdp sources from the working directory after compilation/installation
    echo "Will keep the xrdp and x11rdp sources in the working directory after compilation/installation..."
    echo $LINE
    ;;
    --noinstall)
    INSTFLAG=0 	# do not install anything, just build the packages
    echo "Will not install anything on the system but will build the packages"
    echo $LINE
    ;;
    --nox11rdp)
    X11RDP=0 	# do not build and package x11rdp
    echo "Will not build and package x11rdp"
    echo $LINE
    ;;
    --withjpeg)
      CONFIGUREFLAGS=$CONFIGUREFLAGS" --enable-jpeg"
    ;;
    --withsound)
      CONFIGUREFLAGS=$CONFIGUREFLAGS" --enable-simplesound"
    ;;
    --withdebug)
      CONFIGUREFLAGS=$CONFIGUREFLAGS" --enable-xrdpdebug"
    ;;
    --withneutrino)
      CONFIGUREFLAGS=$CONFIGUREFLAGS" --enable-neutrinordp"
    ;;
    --withkerberos)
      CONFIGUREFLAGS=$CONFIGUREFLAGS" --enable-kerberos"
    ;;
    --withxrdpvr)
      CONFIGUREFLAGS=$CONFIGUREFLAGS" --enable-xrdpvr"
    ;;
    --withnopam)
      CONFIGUREFLAGS=$CONFIGUREFLAGS" --enable-nopam"
    ;;
    --withpamuserpass)
      CONFIGUREFLAGS=$CONFIGUREFLAGS" --enable-pamuserpass"
    ;;
    --withfreerdp)
      CONFIGUREFLAGS=$CONFIGUREFLAGS" --enable-freerdp1"
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
  debconf-apt-progress --dlwaypoint 50 -- apt-get -y install $PkgName
  sleep 1 # Prevent possible dpkg race condition (had that with Xubuntu 12.04 for some reason)
}

download_xrdp_interactive()
{
  git clone $XRDPGIT -b $XRDPBRANCH 2>&1 | dialog  --progressbox "Downloading xrdp source..." 30 100
}

download_xrdp_noninteractive()
{
  echo "Downloading xrdp source from the GIT repository..."
  git clone $XRDPGIT -b $XRDPBRANCH
}

compile_X11rdp_interactive()
{
  cd $WORKINGDIR/xrdp/xorg/X11R7.6/
  (sh buildx.sh $X11DIR ) 2>&1 | dialog  --progressbox "Compiling and installing X11rdp. This will take a while...." 30 100
}

compile_X11rdp_noninteractive()
{
  cd $WORKINGDIR/xrdp/xorg/X11R7.6/
  sh buildx.sh $X11DIR 
  RC=$?
  if [ $RC -ne 0 ]; then
    echo "error building X11rdp"
    exit $RC
 fi
}

package_X11rdp_noninteractive()
{
  PKGDEST=$WORKINGDIR/packages/Xorg

  if [ ! -e $PKGDEST ]; then
    mkdir -p $PKGDEST
  fi


  if [ $BLEED == 1 ]
  then
    cd $WORKINGDIR/xrdp/xorg/debuild
    ./debX11rdp.sh $VERSION $RELEASE $X11DIR $PKGDEST
  else
    mkdir -p $WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN
    cp $WORKINGDIR/control $WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN
    cp -a $WORKINGDIR/postinst $WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN
    cd $WORKINGDIR/xrdp/xorg/debuild
    PACKDIR=x11rdp-files
    DESTDIR=$PACKDIR/opt
    NAME=x11rdp
    ARCH=$( dpkg --print-architecture )
    sed -i -e  "s/DUMMYVERINFO/$VERSION-$RELEASE/"  $PACKDIR/DEBIAN/control
    sed -i -e  "s/DUMMYARCHINFO/$ARCH/"  $PACKDIR/DEBIAN/control
    # need a different delimiter, since it has a path
    sed -i -e  "s,DUMMYDIRINFO,$X11DIR,"  $PACKDIR/DEBIAN/postinst
    mkdir -p $DESTDIR
    cp -Rf $X11DIR $DESTDIR
    dpkg-deb --build $PACKDIR $PKGDEST/${NAME}_$VERSION-${RELEASE}_${ARCH}.deb
    XORGPKGNAME=${NAME}_$VERSION-${RELEASE}_${ARCH}.deb
    # revert to initial state
    rm -rf $DESTDIR
    sed -i -e  "s/$VERSION-$RELEASE/DUMMYVERINFO/"  $PACKDIR/DEBIAN/control
    sed -i -e  "s/$ARCH/DUMMYARCHINFO/"  $PACKDIR/DEBIAN/control
    # need a different delimiter, since it has a path
    sed -i -e  "s,$X11DIR,DUMMYDIRINFO,"  $PACKDIR/DEBIAN/postinst
   fi
}

package_X11rdp_interactive()
{
  PKGDEST=$WORKINGDIR/packages/Xorg

  if [ ! -e $PKGDEST ]
  then
    mkdir -p $PKGDEST
  fi


  if [ $BLEED == 1 ]
  then
    cd $WORKINGDIR/xrdp/xorg/debuild
    ./debX11rdp.sh $VERSION $RELEASE $X11DIR $PKGDEST
  else
    ( mkdir -p $WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN;
    cp $WORKINGDIR/control $WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN;
    cp -a $WORKINGDIR/postinst $WORKINGDIR/xrdp/xorg/debuild/x11rdp-files/DEBIAN;
    cd $WORKINGDIR/xrdp/xorg/debuild;
    PACKDIR=x11rdp-files;
    DESTDIR=$PACKDIR/opt;
    NAME=x11rdp;
    ARCH=$( dpkg --print-architecture );
    sed -i -e  "s/DUMMYVERINFO/$VERSION-$RELEASE/"  $PACKDIR/DEBIAN/control;
    sed -i -e  "s/DUMMYARCHINFO/$ARCH/"  $PACKDIR/DEBIAN/control;
    # need a different delimiter, since it has a path
    sed -i -e  "s,DUMMYDIRINFO,$X11DIR,"  $PACKDIR/DEBIAN/postinst;
    mkdir -p $DESTDIR;
    cp -Rf $X11DIR $DESTDIR;
    dpkg-deb --build $PACKDIR $PKGDEST/${NAME}_$VERSION-${RELEASE}_${ARCH}.deb;
    XORGPKGNAME=${NAME}_$VERSION-${RELEASE}_${ARCH}.deb;
    # revert to initial state
    rm -rf $DESTDIR;
    sed -i -e  "s/$VERSION-$RELEASE/DUMMYVERINFO/"  $PACKDIR/DEBIAN/control;
    sed -i -e  "s/$ARCH/DUMMYARCHINFO/"  $PACKDIR/DEBIAN/control;
    # need a different delimiter, since it has a path
    sed -i -e  "s,$X11DIR,DUMMYDIRINFO,"  $PACKDIR/DEBIAN/postinst ) 2>&1 | dialog  --progressbox "Making X11rdp Debian Package..." 30 100
   fi
}

compile_xrdp_interactive()
{
  ARCH=$( dpkg --print-architecture )
  # work around checkinstall problem - http://bugtrack.izto.org/show_bug.cgi?id=33
  WADIR=/usr/lib/xrdp
  cd $WORKINGDIR/xrdp
  ( ./bootstrap && ./configure $CONFIGUREFLAGS )  2>&1 | dialog  --progressbox "Compiling and installing xrdp..." 30 100
  mkdir $WADIR
  ( make && checkinstall -D --dpkgflags=--force-overwrite --fstrans=yes --arch $ARCH --pakdir $WORKINGDIR/packages/xrdp/ --pkgname=xrdp --pkgversion=$VERSION --pkgrelease=$RELEASE --install=$INSTOPT --default make install ) 2>&1 | dialog  --progressbox "Compiling and installing xrdp..." 20 90
  rm -rf $WADIR
}

compile_xrdp_noninteractive()
{
  ARCH=$( dpkg --print-architecture )
  # work around checkinstall problem - http://bugtrack.izto.org/show_bug.cgi?id=33
  WADIR=/usr/lib/xrdp
  cd $WORKINGDIR/xrdp
  ./bootstrap && ./configure $CONFIGUREFLAGS
  mkdir $WADIR
  make && checkinstall -D --dpkgflags=--force-overwrite --fstrans=yes --arch $ARCH --pakdir $WORKINGDIR/packages/xrdp/ --pkgname=xrdp --pkgversion=$VERSION --pkgrelease=$RELEASE --install=$INSTOPT --default make install 
  rm -rf $WADIR

}

remove_x11rdp_packages()
{
  (apt-get remove --purge x11rdp-*) 2>&1 | dialog --progressbox "Completely removeing previously installed x11rdp packages..." 30 100
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
  DpkgStatus=`dpkg-query -s $PkgName 2>&1`
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
    apt-get -y install $PkgName
  fi
}

# Check for necessary packages and install if necessary...
install_required_packages()
{
  for PkgName in ${RequiredPackages[@]}
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
  Cores=`grep -c ^processor /proc/cpuinfo`
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
	  sed -i -e "s/make -j 1/$makeCommand/g" $WORKINGDIR/buildx_patch.diff
	  # create a file flag to say we've already done this
	  touch $WORKINGDIR/PARALLELMAKE
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
      sed -i -e "s/make -j 1/$makeCommand/g" $WORKINGDIR/buildx_patch.diff
      touch $WORKINGDIR/PARALLELMAKE
    fi
  fi
}

welcome_message()
{
  case "$supported" in
    "1")
      dialogtext="Welcome to the ScaryGliders X11rdp-O-Matic installation script.\n\nThe detected distribution is : $Dist.\n\nThis utility has been tested on this distribution.\n\nClick OK to continue..."
      info_window
    ;;
    "0")
      dialogtext=" Welcome to the ScaryGliders X11rdp-O-Matic installation script.\n\nThe detected distribution is : $Dist .\n\nUnfortunately, no testing has been done for running this utility on this distribution.\n\nIf this is a Debian-based distro, you can try running it. It might work, it might not.\n\nIf the utility does work on this distribution, please let the author know!\n\nClick OK to continue..."
      info_window
      ;;
  esac
}


# Create a useful version number for creating Debian packages.
# Worked out from the chosen branch.
calculate_version_num()
{
  README=https://raw.github.com/neutrinolabs/xrdp/$XRDPBRANCH/readme.txt
  wget -O $TMPFILE $README >& /dev/null
  VERSION=$(grep xrdp $TMPFILE | head -1 | cut -d " " -f2)
  rm -f $TMPFILE
  echo "Debian package version number will be : "$VERSION
  echo $LINE
}

# Make a directory, to which the X11rdp build system will 
# place all the built binaries and files. 
make_X11rdp_env()
{
  if [ -e $X11DIR ] && [ $X11RDP -eq 1 ]
  then
    rm -rf $X11DIR
    mkdir -p $X11DIR
  fi

  if [ -e $WORKINGDIR/xrdp ]
  then
    rm -rf $WORKINGDIR/xrdp
  fi
}

# Alter xrdp source code Makefile.am so the PID file is now in /var/run/xrdp/
# Also patch rdp Makefile to tell Ubuntu linker to include GL symbols - pesky Ubuntu...
alter_xrdp_source()
{
  cd $WORKINGDIR/xrdp
  for file in `rgrep "localstatedir\}" . | cut -d":" -f1`
  do
    sed 's/localstatedir\}\/run/localstatedir\}\/run\/xrdp/' < $file > $file.new
    rm $file
    mv $file.new $file
  done
  cd $WORKINGDIR
  # Patch Jay's buildx.sh.
  # This will patch the make command for parallel makes if that was requested,
  # which should speed up compilation. It will make a backup copy of the original buildx.sh.
  if [ "$PARALLELMAKE" == "1" ]
  then
  	patch -b -d $WORKINGDIR/xrdp/xorg/X11R7.6 buildx.sh < $WORKINGDIR/buildx_patch.diff
  fi
  
  # Patch rdp Makefile
  patch -b -d $WORKINGDIR/xrdp/xorg/X11R7.6/rdp Makefile < $WORKINGDIR/rdp_Makefile.patch
}

control_c()
{
  clear
  cd $WORKINGDIR
  echo "*** CTRL-C was pressed - aborted ***"
  exit
}

cleanup()
{
  rm -rf $WORKINGDIR/xrdp
}

##########################
# Main stuff starts here #
##########################

# Figure out what version number to use for the debian packages
calculate_version_num

# trap keyboard interrupt (control-c)
trap control_c SIGINT


if [ "$X11RDP" == "1" ]; then
  echo " *** Will remove the contents of $X11DIR and $WORKINGDIR/xrdp ***"
  echo
fi
if [ "$INTERACTIVE" == "1" ]
then
  echo "Waiting 5 seconds. Press CTRL+C to abort"
  sleep 5
else
  echo "Press ENTER to continue or CTRL-C to abort"
  read DUMMY
fi
clear

if [ "$INSTFLAG" == "0" ]; then
  INSTOPT="no"
else
  INSTOPT="yes"
fi

make_X11rdp_env

calc_cpu_cores # find out how many cores we have to play with, and if >1, set a possible make command

update_repositories # perform an apt update to make sure we have a current list of available packages 

install_required_packages # install any packages required for xrdp/Xorg/X11rdp compilation


if [ "$INTERACTIVE" == "1" ]
then
	download_xrdp_interactive
	if [[ "$PARALLELMAKE" == "1"  && "$Cores" -gt "1" ]] # Ask about parallel make if requested AND if you have more than 1 CPU core...
	then
	  cpu_cores_interactive
	fi
	alter_xrdp_source
	if  [ "$X11RDP" == "1" ]; then
	  compile_X11rdp_interactive 
	  package_X11rdp_interactive
	fi
	compile_xrdp_interactive
else
	download_xrdp_noninteractive
	if [ "$PARALLELMAKE" == "1" ]
	then
	  cpu_cores_noninteractive
	fi
	alter_xrdp_source
	if  [ "$X11RDP" == "1" ]; then
	  compile_X11rdp_noninteractive 
	  package_X11rdp_noninteractive
	fi
	compile_xrdp_noninteractive
fi

if [ "$INSTFLAG" == "0" ]; then
  # this is stupid but some Makefiles from X11rdp don't have an uninstall target (ex: Python!)
  # ... so instead of not installing X11rdp we remove it in the end
  if  [ "$X11RDP" == "1" ]; then
    rm -rf $X11DIR
  fi
  if [ "$CLEANUP" == "1" ]; then
    cleanup 
  fi
  echo "Will exit now, since we are not installing on this system..."
  exit
fi

# make the /usr/bin/X11rdp symbolic link if it doesn't exist...
if [ ! -e /usr/bin/X11rdp ]
then
    if [ -e $X11DIR/bin/X11rdp ]
    then
        ln -s $X11DIR/bin/X11rdp /usr/bin/X11rdp
    else
        clear
        echo "There was a problem... the /opt/X11rdp/bin/X11rdp binary could not be found. Did the compilation complete?"
        echo "Stopped. Please investigate what went wrong."
        exit
    fi
fi

# make the doc directory if it doesn't exist...
if [ ! -e /usr/share/doc/xrdp ]
	then
		mkdir /usr/share/doc/xrdp
fi

dpkg -i $WORKINGDIR/packages/Xorg/*.deb
dpkg -i $WORKINGDIR/packages/xrdp/*.deb

# create the rc.d calls for startup/shutdown...
update-rc.d xrdp defaults

# Crank the engine ;)
/etc/init.d/xrdp start

dialogtext="X11rdp and xrdp should now be fully installed, configured, and running on this system. One last thing to do now is to configure which desktop will be presented to the user after they log in via RDP.  Use the RDPsesconfig utility to do this."

if [ $INTERACTIVE == 1 ]
then
	info_window
else
	echo $dialogtext
fi

