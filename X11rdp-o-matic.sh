#!/bin/bash

# Automatic X11rdp Compiler/Installer
# a.k.a. ScaryGliders X11rdp-O-Matic installation script
#
# Version 2.5
#
# Version release date : 20120825
##################(yyyyMMDD)
#
# See CHANGELOG for release detials
#
# Will run on Debian-based systems only at the moment. RPM based distros perhaps some time in the future...
#
# Copyright (C) 2012, Kevin Cave <kevin@scarygliders.net>
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



#################################################################
# Initialise variables and parse any command line switches here #
#################################################################

# set LANG so that dpkg etc. return the expected responses so the script is guaranteed to work under different locales
export LANG="C"

workingdir=`pwd` # Would have used /tmp for this, but some distros I tried mount /tmp as tmpfs, and filled up.


# Declare a list of packages required to download sources, and compile them...
RequiredPackages=(build-essential subversion automake1.7 automake1.9 git git-core libssl-dev libpam0g-dev zlib1g-dev libtool libx11-dev libxfixes-dev pkg-config xrdp)

questiontitle="X11rdp Install-O-Matic Question..."
title="X11rdp Install-O-Matic"
backtitle="Scarygliders X11rdp Install-O-Matic"

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


INTERACTIVE=1     # Interactive by default.
OPTIMIZE=1		    # Utilise all available CPU's for compilation by default.
RE_USE_XSOURCE=0  # Do not reuse existing X11rdp&xrdp source by default unless specified.
TEXT=1				    # Use text dialogs by default, unless otherwise requested below
CLEANUP=1			    # Cleanup the x11rdp and xrdp sources by default - to keep requires --nocleanup command line switch


# Parse the command line for any arguments
while [ $# -gt 0 ];
do
	case "$1" in
	  --help)
   echo "
   
  usage: 
  $0 --<option>
  --help          : show this help.
  --justdoit      : perform a complete compile and install with sane defaults and no user interaction.
  --nocpuoptimize : do not change X11rdp build script to utilize more than 1 of your CPU cores.
  --zenityfrontend  : use the not so great Zenity front-end. (Default is to use text)
  --reuse         : re-use downloaded X11rdp / xrdp source code if it exists. (Default is to download source)
  --nocleanup     : do not remove X11rdp / xrdp source code after installation. (Default is to clean up).
  
  "
	    exit
	  ;;
		--justdoit)
			INTERACTIVE=0 # Don't bother with fancy schmancy dialogs, just go through and do everything!
			TEXT=1				# Note this will override even interactive Text Mode
			echo "Okay, will just do the install from start to finish with no user interaction..."
		;;
		--nocpuoptimize)
			OPTIMIZE=0		# Don't utilize additional CPU cores for compilation.
			echo "Will not utilize additional CPU's for compilation..."
		;;
		--zenityfrontend)
			TEXT=0				# Go to Zenity Mode (unless this is a text-only console, in which this will be ignored)
			echo "Will attempt to use the Zenity front-end..."
		;;
		--reuse)
			RE_USE_XSOURCE=1
			echo "Will re-use the existing X11rdp and xrdp source trees if they exist..."
		;;
		--nocleanup)
			CLEANUP=0 		# Don't remove the xrdp and x11rdp sources from the working directory after compilation/installation
			echo "Will keep the xrdp and x11rdp sources in the working directory after compilation/installation..."
		;;
  esac
  shift
done

###########################################################
# Before doing anything else, check if we're running with #
# priveleges, because we need to be.                      #
###########################################################
id=`id -u`
if [ $id -ne 0 ]
	then
		clear
		echo "You tried running the ScaryGliders X11rdp-O-Matic installation script as a non-priveleged user. Please run as root."
		exit 1
fi

if [ "$DISPLAY" == '' ] # If we're running on a non-X terminal, switch to Text Mode
	then
		TEXT=1
fi

# Source the "Front End"
case $TEXT in
	0)
		. ZenityFrontEndIncludes
		;;
	1)
		. TextFrontEndIncludes
		;;
esac

#############################################
# Common function declarations begin here...#
#############################################

apt_update_noninteractive()
{
  apt-get update
}

# Interrogates dpkg to find out the status of a given package name, and installs if needed...
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

  if [[ "$PkgStatus" = "0"  ||  $PkgStatus = "1" ]] # Install or re-install package and give a relatively nice-ish message whilst doing so - Zenity is kind of limited...
	then
		if [ "$INTERACTIVE" == "1" ]
		then
			install_package_interactive
		else
			apt-get -y install $PkgName
		fi
	fi
}

# Check for necessary packages and install if necessary...
install_required_packages()
{
  for PkgName in ${RequiredPackages[@]}
  do
  	check_package
  done
}

cpu_cores_interactive()
{
	# See how many cpu cores we have to play with - we can speed up compilation if we have more cores ;)
	Cores=`grep -c ^processor /proc/cpuinfo`
	if [ $Cores -gt 1 ]
	then
		if [ ! -e $workingdir/x11rdp_xorg71/OPTIMIZED ] # No need to perform this if for some reason we've been here before...
		then
			let "MakesystemWorkHarder = $Cores + 1"
			OptimizeCommand="make -j $MakesystemWorkHarder"
			dialogtext="Good news!\n\nYou can speed up the compilation because there are $Cores CPU cores available to this system.\n\nI can change the X11rdp build script for you, to utilize the additional CPU cores.\nWould you like me to do this for you?\n\n(Answering Yes will add the \"-j [#cores+1]\" switch to the make command in the build script.\n\nIn this case it will be changed to \"$OptimizeCommand\")."
			ask_question
			Question=$?
	
			case "$Question" in
				"0") # Yes please warm up my computer even more! ;)
					sed -i -e "s/make/$OptimizeCommand/g" $workingdir/x11rdp_xorg71/buildx.sh
					touch $workingdir/x11rdp_xorg71/OPTIMIZED
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
	# See how many cpu cores we have to play with - we can speed up compilation if we have more cores ;)
	Cores=`grep -c ^processor /proc/cpuinfo`
	if [ $Cores -gt 1 ]
	then
		if [ ! -e $workingdir/x11rdp_xorg71/OPTIMIZED ] # No need to perform this if for some reason we've been here before...
		then
			let "MakesystemWorkHarder = $Cores + 1"
			OptimizeCommand="make -j $MakesystemWorkHarder"
			sed -i -e "s/make/$OptimizeCommand/g" $workingdir/x11rdp_xorg71/buildx.sh
			touch $workingdir/x11rdp_xorg71/OPTIMIZED
		fi
	fi
}

# Check for an existing X11rdp source tree (interactively)...
interactive_check_x11rdp_source()
{
	if [ -e $workingdir/x11rdp_xorg71 ]
	then
		dialogtext="It appears you already have the X11rdp source tree in this user's home directory.\n\nWould you like me to re-use the existing source?\n\nIt should be OK to re-use the existing source tree, as long as it downloaded properly, so you can probably answer YES here.\n\n(Answering No here will delete the existing source and download a fresh copy)."
		ask_question
		Question=$?
	
		case "$Question" in
			"1")
				echo Removing old tree...
				rm -rf $workingdir/x11rdp_xorg71
				dialogtext="Old source tree removed at your request.    Will download a fresh copy.   Click OK to proceed..."
				info_window
				downloadX11rdp_inter
				;;
			"0")
				dialogtext="Okay, will attempt to re-use the existing source tree in $workingdir/x11rdp_xorg71.      Click OK to proceed..."
				info_window
				;;
		esac
	else
		downloadX11rdp_inter
	fi
}

# Check for an existing X11rdp source tree (non-interactively)...
noninteractive_check_x11rdp_source()
{
	if [ -e $workingdir/x11rdp_xorg71 ]
	then
		if [ "$RE_USE_XSOURCE" == "0" ]
		then
			rm -r $workingdir/x11rdp_xorg71
			downloadX11rdp_noninter
		fi
	else
		downloadX11rdp_noninter
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

check_xrdp_interactive()
{
	if [ -e $workingdir/xrdp.git ]
	then
		dialogtext="You already appear to have the xrdp source code downloaded.\n\nWould you like to keep and re-use it again?\n\nAnswering YES here will keep the source and recompile it."
		ask_question
		DelOldTree=$?
		case "$DelOldTree" in
			"1")
				rm -rf $workingdir/xrdp.git
				download_xrdp_inter
				alter_xrdp_source
				;;
			"0")
				olddir=`pwd`
				cd $workingdir/xrdp.git
				make clean
				cd $olddir
				;;
		esac
	else
			download_xrdp_inter
			alter_xrdp_source
	fi
}

check_xrdp_noninteractive()
{
	if [ -e $workingdir/xrdp.git ]
	then
		if [ "$RE_USE_XSOURCE" == "0" ]
		then
			rm -rf $workingdir/xrdp.git
			download_xrdp_noninter
			alter_xrdp_source
		else
			olddir='pwd'
			cd $workingdir/xrdp.git
			make clean
			cd $olddir
		fi
	else
		download_xrdp_noninter
		alter_xrdp_source
	fi
}

#Alter xrdp source code Makefile.am so the PID file is now in /var/run/xrdp/
alter_xrdp_source()
{
  cd $workingdir/xrdp.git
  git checkout 4cd0c118c273730043cc77b749537dedc7051571 # revert to an earlier, working version
  for file in `find . -name Makefile.am -print`
  do
    sed 's/localstatedir\}\/run/localstatedir\}\/run\/xrdp/' < $file > $file.new
    rm $file
    mv $file.new $file
  done
  cd $workingdir
}

cleanup()
{
	if [ -e $workingdir/xrdp.git ]
	then
		rm -r $workingdir/xrdp.git
	fi
	
	if [ -e $workingdir/x11rdp_xorg71 ]
	then
		rm -r $workingdir/x11rdp_xorg71
	fi
}

control_c()
{
  clear
  cd $workingdir
  cleanup
  echo "*** CTRL-C was pressed - aborting - source trees were removed ***"
  exit
}

##########################
# Main stuff starts here #
##########################


# trap keyboard interrupt (control-c)
trap control_c SIGINT

if [ ! -e /usr/bin/dialog ]
then
  apt-get install dialog
fi

if [ "$INTERACTIVE" == "1" ]
then
  welcome_message
  apt_update_interactive
else
  apt-get update
fi

install_required_packages

# Make a directory, to which the X11rdp build system will 
# place all the built binaries and files. If /opt/X11rdp exists,
# then we might as well just remove it - this makes more sense than asking.
if [ ! -e /opt/X11rdp ]
then
	mkdir -p /opt/X11rdp
else
		rm -r /opt/X11rdp
		if [ -e /usr/bin/X11rdp ]
		then
			rm /usr/bin/X11rdp
		fi
		mkdir -p /opt/X11rdp
fi


if [ "$INTERACTIVE" == "1" ]
then
  remove_xrdp_package_interactive # Remove xrdp but don't purge it...
	interactive_check_x11rdp_source
	check_xrdp_interactive
	if [ "$OPTIMIZE" == "1" ] # Check for additional CPU cores only if utilisation was requested
	then
	  cpu_cores_interactive
	fi
	compile_X11rdp_interactive
	compile_xrdp_interactive
else
  remove_xrdp_package_noninteractive # Remove xrdp but don't purge it...
	noninteractive_check_x11rdp_source
	check_xrdp_noninteractive
	if [ "$OPTIMIZE" == "1" ]
	then
	  cpu_cores_noninteractive
	fi
	# Compile X11rdp
  cd $workingdir/x11rdp_xorg71
  sh buildx.sh /opt/X11rdp
  # Compile and install xrdp
  cd $workingdir/xrdp.git
  git checkout 4cd0c118c273730043cc77b749537dedc7051571 # revert to an earlier, working version
	./bootstrap
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
	make
	make install
fi



# make the /usr/bin/X11rdp symbolic link if it doesn't exist...
if [ ! -e /usr/bin/X11rdp ]
	then
		ln -s /opt/X11rdp/bin/X11rdp /usr/bin/X11rdp
fi

if [ ! -e /usr/share/doc/xrdp ]
	then
		mkdir /usr/share/doc/xrdp
fi

# Do other necessary stuff that doesn't need user intervention, like handle the rsa keys, create the startwm.sh symbolic link, etc...
sh -c "mv /etc/xrdp/rsakeys.ini /usr/share/doc/xrdp/; chmod 600 /usr/share/doc/xrdp/rsakeys.ini; chown xrdp:xrdp /usr/share/doc/xrdp/rsakeys.ini; mv /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.BACKUP; ln -s /etc/X11/Xsession /etc/xrdp/startwm.sh"

# Write /etc/xrdp/xrdp.ini such that X11rdp is the default on the menu...
#--------Begin here document-----------#
tee /etc/xrdp/xrdp.ini >/dev/null << "EOF"
[globals]
bitmap_cache=yes
bitmap_compression=yes
port=3389
crypt_level=low
channel_code=1
max_bpp=24
#black=000000
#grey=d6d3ce
#dark_grey=808080
#blue=08246b
#dark_blue=08246b
#white=ffffff
#red=ff0000
#green=00ff00
#background=626c72

[xrdp1]
name=sesman-X11rdp
lib=libxup.so
username=ask
password=ask
ip=127.0.0.1
port=-1
xserverbpp=24

[xrdp2]
name=sesman-Xvnc
lib=libvnc.so
username=ask
password=ask
ip=127.0.0.1
port=-1

[xrdp3]
name=console
lib=libvnc.so
ip=127.0.0.1
port=5900
username=na
password=ask

[xrdp4]
name=vnc-any
lib=libvnc.so
ip=ask
port=ask5900
username=na
password=ask

[xrdp5]
name=sesman-any
lib=libvnc.so
ip=ask
port=-1
username=ask
password=ask

[xrdp6]
name=rdp-any
lib=librdp.so
ip=ask
port=ask3389

[xrdp7]
name=freerdp-any
lib=libxrdpfreerdp.so
ip=ask
port=ask3389
EOF
#----------End here document-----------#

# Write a slightly altered version of the /etc/init.d/xrdp init script...
#--------Begin here document-----------#
tee /etc/init.d/xrdp >/dev/null << "EOF"
#!/bin/sh -e
#
# start/stop xrdp and sesman daemons
#
### BEGIN INIT INFO
# Provides:          xrdp
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start xrdp and sesman daemons
# Description:       XRDP uses the Remote Desktop Protocol to present a
#                    graphical login to a remote client allowing connection
#                    to a VNC server or another RDP server.
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DAEMON=/usr/sbin/xrdp
PIDDIR=/var/run/xrdp/
SESMAN_START=yes
USERID=xrdp
RSAKEYS=/etc/xrdp/rsakeys.ini
NAME=xrdp
DESC="Remote Desktop Protocol server"

test -x $DAEMON || exit 0

. /lib/lsb/init-functions

check_root()  {
    if [ "$(id -u)" != "0" ]; then
        log_failure_msg "You must be root to start, stop or restart $NAME."
        exit 4
    fi
}

if [ -r /etc/default/$NAME ]; then
   . /etc/default/$NAME
fi

# Tasks that can only be run as root
if [ "$(id -u)" = "0" ]; then
    # Check for pid dir
    if [ ! -d $PIDDIR ] ; then
        mkdir $PIDDIR
    fi
    chown $USERID:$USERID $PIDDIR

    # Check for rsa key 
    if [ ! -f $RSAKEYS ] || cmp $RSAKEYS /usr/share/doc/xrdp/rsakeys.ini > /dev/null; then
        log_action_begin_msg "Generating xrdp RSA keys..."
        (umask 077 ; xrdp-keygen xrdp $RSAKEYS)
        chown $USERID:$USERID $RSAKEYS
        if [ ! -f $RSAKEYS ] ; then
            log_action_end_msg 1 "could not create $RSAKEYS"
            exit 1
        fi
        log_action_end_msg 0 "done"
    fi
fi


case "$1" in
  start)
        check_root
        exitval=0
        log_daemon_msg "Starting $DESC " 
        if pidofproc -p $PIDDIR/$NAME.pid $DAEMON > /dev/null; then
            log_progress_msg "$NAME apparently already running"
            log_end_msg 0
            exit 0
        fi
        log_progress_msg $NAME
        start-stop-daemon --start --quiet --oknodo  --pidfile $PIDDIR/$NAME.pid \
	    --chuid $USERID:$USERID --exec $DAEMON
        exitval=$?
	if [ "$SESMAN_START" = "yes" ] ; then
            log_progress_msg "sesman"
            start-stop-daemon --start --quiet --oknodo --pidfile $PIDDIR/xrdp-sesman.pid \
	       --exec /usr/sbin/xrdp-sesman
            value=$?
            [ $value -gt 0 ] && exitval=$value
        fi
        # Make pidfile readables for all users (for status to work)
        [ -e $PIDDIR/xrdp-sesman.pid ] && chmod 0644 $PIDDIR/xrdp-sesman.pid
        [ -e $PIDDIR/$NAME.pid ] && chmod 0644 $PIDDIR/$NAME.pid
        # Note: Unfortunately, xrdp currently takes too long to create
        # the pidffile unless properly patched
        log_end_msg $exitval
	;;
  stop)
        check_root
	[ -n "$XRDP_UPGRADE" -a "$RESTART_ON_UPGRADE" = "no" ] && {
	    echo "Upgrade in progress, no restart of xrdp."
	    exit 0
	}
        exitval=0
        log_daemon_msg "Stopping RDP Session manager " 
        log_progress_msg "sesman"
        if pidofproc -p  $PIDDIR/xrdp-sesman.pid /usr/sbin/xrdp-sesman  > /dev/null; then
            start-stop-daemon --stop --quiet --oknodo --pidfile $PIDDIR/xrdp-sesman.pid \
                --chuid $USERID:$USERID --exec /usr/sbin/xrdp-sesman
            exitval=$?
        else
            log_progress_msg "apparently not running"
        fi
        log_progress_msg $NAME
        if pidofproc -p  $PIDDIR/$NAME.pid $DAEMON  > /dev/null; then
            start-stop-daemon --stop --quiet --oknodo --pidfile $PIDDIR/$NAME.pid \
	    --exec $DAEMON
            value=$?
            [ $value -gt 0 ] && exitval=$value
        else
            log_progress_msg "apparently not running"
        fi
        log_end_msg $exitval
	;;
  restart|force-reload)
        check_root
	$0 stop
        # Wait for things to settle down
        sleep 1
	$0 start
	;;
  reload)
        log_warning_msg "Reloading $NAME daemon: not implemented, as the daemon"
        log_warning_msg "cannot re-read the config file (use restart)."
        ;;
  status)
        exitval=0
        log_daemon_msg "Checking status of $DESC" "$NAME"
        if pidofproc -p  $PIDDIR/$NAME.pid $DAEMON  > /dev/null; then
            log_progress_msg "running"
            log_end_msg 0
        else
            log_progress_msg "apparently not running"
            log_end_msg 1 || true
            exitval=1
        fi
	if [ "$SESMAN_START" = "yes" ] ; then
            log_daemon_msg "Checking status of RDP Session Manager" "sesman"
            if pidofproc -p  $PIDDIR/xrdp-sesman.pid /usr/sbin/xrdp-sesman  > /dev/null; then
                log_progress_msg "running"
                log_end_msg 0
            else
                log_progress_msg "apparently not running"
                log_end_msg 1 || true
                exitval=1
            fi
	fi
        exit $exitval
        ;;
  *)
	N=/etc/init.d/$NAME
	echo "Usage: $N {start|stop|restart|force-reload|status}" >&2
	exit 1
	;;
esac

exit 0
EOF
#----------End here document-----------#

# Make written script executable...
chmod a+x /etc/init.d/xrdp

# Crank the engine ;)
/etc/init.d/xrdp start

# Clean up after ourselves if requested
if [ $CLEANUP == 1 ]
then
	cleanup
fi

dialogtext="\nCongratulations!\n\nX11rdp and xrdp should now be fully installed, configured, and running on this system.\n\nOne last thing to do now is to configure which desktop will be presented to the user after they log in via RDP. \n\nUse the RDPsesconfig utility to do this."
if [ $INTERACTIVE == 1 ]
then
	info_window
else
	echo $dialogtext
fi

