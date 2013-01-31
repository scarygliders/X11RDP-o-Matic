#!/bin/bash

# Automatic X11rdp Compiler/Installer
# a.k.a. ScaryGliders X11rdp-O-Matic installation script
#
# Version 3.0-BETA
#
# Version release date : 20130125
##################(yyyyMMDD)
#
# See CHANGELOG for release details
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

if [ ! -e /usr/bin/dialog ]
then
    apt-get -y install dialog
fi

# Declare a list of packages required to download sources, and compile them...
RequiredPackages=(build-essential checkinstall automake automake1.9 git git-core libssl-dev libpam0g-dev zlib1g-dev libtool libx11-dev libxfixes-dev pkg-config flex bison libxml2-dev intltool xsltproc xutils-dev python-libxml2 g++ xutils)

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


INTERACTIVE=1     	# Interactive by default.
PARALLELMAKE=1		# Utilise all available CPU's for compilation by default.
RE_USE_XSOURCE=0  	# Do not reuse existing X11rdp&xrdp source by default unless specified.
CLEANUP=1		# Cleanup the x11rdp and xrdp sources by default - to keep requires --nocleanup command line switch


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
			PARALLELMAKE=0		# Don't utilize additional CPU cores for compilation.
			echo "Will not utilize additional CPU's for compilation..."
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
		echo "You tried running the Scarygliders X11rdp-O-Matic installation script as a non-priveleged user. Please run as root."
		exit 1
fi

# Source the "Front End"
. TextFrontEndIncludes

#############################################
# Common function declarations begin here...#
#############################################

update_repositories()
{
	if [ "$INTERACTIVE" == "1" ]
	then
	  welcome_message
	  apt_update_interactive
	else
	  apt-get update
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
  	if [[ "$PkgStatus" = "0"  ||  $PkgStatus = "1" ]]
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
	fi
}

cpu_cores_interactive()
{
	# See how many cpu cores we have to play with - we can speed up compilation if we have more cores ;)
	if [ ! -e $workingdir/PARALLELMAKE ] # No need to perform this if for some reason we've been here before...
	then
		dialogtext="Good news!\n\nYou can speed up the compilation because there are $Cores CPU cores available to this system.\n\nI can patch the X11rdp build script for you, to utilize the additional CPU cores.\nWould you like me to do this for you?\n\n(Answering Yes will add the \"-j [#cores+1]\" switch to the make command in the build script.\n\nIn this case it will be changed to \"$makeCommand\")."
		ask_question
		Question=$?
	
		case "$Question" in
			"0") # Yes please warm up my computer even more! ;)
				# edit the buildx.sh patch file ;)
				sed -i -e "s/make -j 1/$makeCommand/g" $workingdir/buildx_patch.diff
				# create a file flag to say we've already done this
				touch $workingdir/PARALLELMAKE
				dialogtext="Ok, the optimization has been made.\n\nLooks like your system is going to be working hard soon ;)\n\nClick OK to proceed with the compilation."
				info_window
				;;
			"1") # No thanks, I like waiting ;)
				dialogtext="Ok, I will not change the build script as suggested.\n\nIt will take longer to compile though :)\n\nPress OK to proceed with the compilation..."
				info_window
				;;
		esac
	fi
}

cpu_cores_noninteractive()
{
	if [ ! -e $workingdir/PARALLELMAKE ] # No need to perform this if for some reason we've been here before...
	then
		sed -i -e "s/make -j 1/$makeCommand/g" $workingdir/buildx_patch.diff
		touch $workingdir/PARALLELMAKE
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

# Make a directory, to which the X11rdp build system will 
# place all the built binaries and files. 
make_X11rdp_directory()
{
	if [ ! -e /opt/X11rdp ]
	then
		mkdir -p /opt/X11rdp
		if [ -e /usr/bin/X11rdp ]
		then
			rm /usr/bin/X11rdp
		fi
	fi
}

#Alter xrdp source code Makefile.am so the PID file is now in /var/run/xrdp/
alter_xrdp_source()
{
  cd $workingdir/xrdp
  for file in `rgrep "localstatedir\}" . | cut -d":" -f1`
  do
    sed 's/localstatedir\}\/run/localstatedir\}\/run\/xrdp/' < $file > $file.new
    rm $file
    mv $file.new $file
  done
  cd $workingdir
  # Patch Jay's buildx.sh.
  # This will add checkinstall to create distribution packages
  # Also, will patch the make command for parallel makes if that was requested,
  # which should speed up compilation. It will make a backup copy of the original buildx.sh.
  patch -b -d $workingdir/xrdp/xorg/X11R7.6 buildx.sh < $workingdir/buildx_patch.diff
}

control_c()
{
  clear
  cd $workingdir
  echo "*** CTRL-C was pressed - aborted ***"
  exit
}

##########################
# Main stuff starts here #
##########################


# trap keyboard interrupt (control-c)
trap control_c SIGINT

calc_cpu_cores # find out how many cores we have to play with, and if >1, set a possible make command

update_repositories # perform an apt update to make sure we have a current list of available packages 

install_required_packages # install any packages required for xrdp/Xorg/X11rdp compilation

make_X11rdp_directory # make or clear-and-remake /opt/X11rdp directory

if [ "$INTERACTIVE" == "1" ]
then
	download_xrdp_interactive
	if [[ "$PARALLELMAKE" == "1"  && "$Cores" -gt "1" ]] # Ask about parallel make if requested AND if you have more than 1 CPU core...
	then
	  cpu_cores_interactive
	fi
	alter_xrdp_source
	compile_X11rdp_interactive
	compile_xrdp_interactive
else
	download_xrdp_noninteractive
	if [ "$PARALLELMAKE" == "1" ]
	then
	  cpu_cores_noninteractive
	fi
	alter_xrdp_source
	compile_X11rdp_noninteractive
	compile_xrdp_noninteractive
fi


# make the /usr/bin/X11rdp symbolic link if it doesn't exist...
if [ ! -e /usr/bin/X11rdp ]
then
    if [ -e /opt/X11rdp/bin/X11rdp ]
    then
        ln -s /opt/X11rdp/bin/X11rdp /usr/bin/X11rdp
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

# Do other necessary stuff that doesn't need user intervention, like handle the rsa keys, create the startwm.sh symbolic link, etc...
sh -c "mv /etc/xrdp/rsakeys.ini /usr/share/doc/xrdp/; chmod 600 /usr/share/doc/xrdp/rsakeys.ini; chown xrdp:xrdp /usr/share/doc/xrdp/rsakeys.ini; mv /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.BACKUP; ln -s /etc/X11/Xsession /etc/xrdp/startwm.sh"

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
USERID=root
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


clear

# Make written script executable...
chmod a+x /etc/init.d/xrdp


# Update rc scripts so xrdp starts upon boot...
sudo update-rc.d xrdp defaults

# Crank the engine ;)
/etc/init.d/xrdp start

dialogtext="\nCongratulations!\n\nX11rdp and xrdp should now be fully installed, configured, and running on this system.\n\nOne last thing to do now is to configure which desktop will be presented to the user after they log in via RDP. \n\nUse the RDPsesconfig utility to do this."
if [ $INTERACTIVE == 1 ]
then
	info_window
else
	echo $dialogtext
fi

