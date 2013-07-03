#!/bin/bash

# Automatic RDP session configurator
# a.k.a. ScaryGliders RDPsesconfig
#
# Version 3.0-beta3
#
# Version release date : 20130623
########################(yyyyMMDD)
#
# See CHANGELOG for release detials
#
# Will run on Debian-based systems only at the moment. RPM based distros perhaps some time in the future...
#
# Copyright (C) 2013, Kevin Cave <kevin@scarygliders.net>
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

# set LANG so that dpkg etc. return the expected responses so the script is guaranteed to work under different locales
export LANG="C"

###########################################################
# Before doing anything else, check if we're running with #
# priveleges, because we need to be.                      #
###########################################################
id=`id -u`
if [ $id -ne 0 ]
	then
		clear
		echo "You tried running the ScaryGliders RDPsesconfig utility as a non-priveleged user. Please run as root."
		exit 1
fi

#################################################################
# Initialise variables and parse any command line switches here #
#################################################################

INTERACTIVE=1

Dist=`lsb_release -d -s` # What are we running on

if [ -e /usr/share/xubuntu ]
then
	Dist="$Dist (Xubuntu)" # need to distinguish Xubuntu from Ubuntu
fi

if [ -e /usr/share/lubuntu ]
then
	Dist="$Dist (Lubuntu)" # need to distinguish Lubuntu from Ubuntu
fi

backtitle="Scarygliders RDPsesconfig"
questiontitle="RDPsesconfig Question..."
title="RDPsesconfig"
DIALOG="dialog"

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


###############################################
# Text/dialog front-end function declarations #
###############################################

let "HEIGHT = $LINES - 3"
let "WIDTH = $COLUMNS - 8"

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




#############################################
# Common function declarations begin here...                  #
#############################################

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

  if [ "$PkgStatus" = "0" ] || [ $PkgStatus = "1" ] # Install or re-install package and give a relatively nice-ish message whilst doing so - Zenity is kind of limited...
	then
		install_package_interactive
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

# Reads all normal (non-system) accounts in from /etc/passwd, and presents them as a list
# If your system also has "machine accounts" (i.e. accounts for PC's to be added under a
# SAMBA domain controller - marked with a "$" at the end) these will be ignored.
# smbguest is also ignored.
select_local_user_accounts_to_config()
{
	if [ -e ./usernames.tmp ]
	then
	  rm ./usernames.tmp
	fi
	userlist=""
	usercount=0
	linecount=`cat /etc/passwd | wc -l`
	processed=0
	percent=0
	title="Processing local users in /etc/passwd..."
	hit=""
(	while read line
	do 
    userno=`echo $line | cut -d":" -f3`
		if [ $userno -gt 999 ] && [ $userno -lt 65534 ]
		then
			username=`echo $line | cut -d":" -f1`
			if [[ $username != *$ && $username != *smbguest* ]]
			then
				realname=`echo $line | cut -d":" -f5 | cut -d"," -f1`
        		hit="\nAdded username $username to list."
				let "usercount += 1"
			  echo "$username.$realname">> ./usernames.tmp
			fi
		fi
			let "processed += 1"
			percent=$((${processed}*100/${linecount}))
			echo "Processed $processed of $linecount entries in /etc/passwd ...$hit"
			echo XXX
			echo $percent
	done </etc/passwd ) | dialog --backtitle "$backtitle" --title "$title" "$@" --gauge "Processing..." 15 75 0
  
  allusers=""
  usercount=0
  while read line
  do
    username=$(echo $line | cut -d"." -f1)
    allusers="$allusers $username"
    realname=$(echo $line | cut -d"." -f2)
		if [ $usercount == 0 ]
		then
			userlist=("ALL USERS" "Select all users on this list" off "${username[@]}" "${realname[@]}" off )
		else
			userlist=("${userlist[@]}" "${username[@]}" "${realname[@]}" off )
		fi
		let "usercount += 1"
	done < ./usernames.tmp
   
	windowsize=(0 0 0)
	dialog_param=("--separate-output" "--backtitle" "$backtitle" "--checklist" "Select the user accounts you wish to configure..." "${windowsize[@]}" "${userlist[@]}")
	selectedusers=$(dialog "${dialog_param[@]}" 2>&1 >/dev/tty)
  echo allusers = $allusers

  if [ "$selectedusers" == "" ]
  then
    dialog --backtitle "$backtitle" --title "No Users Were Selected" --msgbox "\nYou did not select any users!\n\nQuitting the utility now.\n\nClick OK to exit.\n\n" 0 0
    exit
  fi
  
  if [ "$selectedusers" == "ALL USERS" ]
  then
    selectedusers=$allusers
  fi
  rm ./usernames.tmp
}

create_desktop_dialog_list()
{
	case $Dist in
	*Xubuntu*)
		desktoplist=( "Xfce" "Xfce Desktop" on ) # Offering anything other than Xfce on Xubuntu (even though we can) misses the whole point of Xubuntu.
		;;
	"Ubuntu 12.10"*)
	    desktoplist=( "Unity" "Default Ubuntu Unity (not recommended for RDP" on "Xfce" "Xfce Desktop" off "LXDE" "LXDE Desktop" off "KDE" "KDE Desktop" off "MATE" "Install MATE (experimental)" off )
	    ;;
	"Ubuntu 12.04"* | "Ubuntu 11.10"*)
		desktoplist=( "Gnome Classic" "Classic Gnome Desktop" on  "Xfce" "Xfce Desktop" off "LXDE" "LXDE Desktop" off "KDE" "KDE Desktop" off "Unity-2D" "Unity 2D Desktop" off "MATE" "Install MATE (experimental)" off )
		;;
	Debian*)
		desktoplist=( "Gnome Classic" "Classic Gnome Desktop" on  "Xfce" "Xfce Desktop" off "LXDE" "LXDE Desktop" off "KDE" "KDE Desktop" off )
		;;
	*Mint*)
		desktoplist=( "MATE" "MATE Desktop (recommended)" on "Cinnamon" "Cinnamon Desktop (NOT recommended for RDP) " off "Gnome Classic" "Classic Gnome Desktop" off  "Xfce" "Xfce Desktop" off "LXDE" "LXDE Desktop" off )
		;;
	*Lubuntu*)
		desktoplist=( "Lubuntu" "Lubuntu Session" on )
	esac
}

# creates a .xsession file for each selected local user account
# based on the selected desktop environment
create_xsession()
{
(		for username in $selectedusers
		do
			homedir=`grep "^$username:" /etc/passwd | cut -d":" -f6`
			echo "Creating .xsession file for $username in $homedir with entry \"$session\".." 2>&1
			echo $session > $homedir/.xsession
			chown $username:$username $homedir/.xsession
			chmod u+x $homedir/.xsession
		done) | dialog --backtitle "$backtitle" --title "creating .xsession files..." --progressbox "Processing..." 12 80
		sleep 3
}

select_desktop()
{
	title="RDPsesconfig"
	backtitle="Scarygliders RDPsesconfig"
	windowsize=(0 0 0)
	dialog_param=("--backtitle" "$backtitle" "--radiolist" "$title" "${windowsize[@]}" "${desktoplist[@]}")
	desktop=$($DIALOG "${dialog_param[@]}" 2>&1 >/dev/tty)
}



# Configure a gnome environment
config_for_gnome_classic()
{
	case "$Dist" in
		"Debian GNU/Linux 6"*)
			session="gnome-session"
			RequiredPackages=(gnome-core)
			;;
		"Ubuntu 10.04"*)
			session="gnome-session -f"
			RequiredPackages=(gnome-core)
			;;
		*)
			session="gnome-session --session=gnome-fallback"
		    RequiredPackages=(gnome-session-fallback gnome-tweak-tool)
			;;
	esac
	selecttext="Select which user(s) to configure a Gnome Classic RDP session for..."
#	questiontitle="Gnome Classic RDP session configuration"
}

# configure a unity environment (2d)
config_for_unity2d()
{
	session="gnome-session --session=ubuntu-2d"
	RequiredPackages=(gnome-session gnome-session-fallback unity-2d gnome-tweak-tool)
	selecttext="Select which user(s) to configure a Unity 2D RDP session for..."
}

#configure an xfce environment
config_for_xfce()
{
	session="startxfce4"
	RequiredPackages=(xfdesktop4)
	selecttext="Select which user(s) to configure an Xfce RDP session for..."
}

#configure a KDE environment
config_for_kde()
{
	session="startkde"
	RequiredPackages=(kde-plasma-desktop)
	selecttext="Select which user(s) to configure a KDE RDP session for..."
}

# configure a MATE environment on Linux Mint
config_for_mate_on_mint()
{
	session="mate-session"
	RequiredPackages=(mint-meta-mate)
	selecttext="Select which user(s) to configure a MATE RDP session for..."
}

# configure an lxde environment
config_for_lxde()
{
	session="startlxde"
	RequiredPackages=(lxde-core lxterminal)
	selecttext="Select which user(s) to configure an LXDE RDP session for..."
}

# configure an lxde environment
config_for_lubuntu()
{
	session="startlubuntu"
	RequiredPackages=(lubuntu-desktop lubuntu-default-session)
	selecttext="Select which user(s) to configure a Lubuntu RDP session for..."
}

# configure a MATE environment on Ubuntu 12.10 (experimental - could break)
config_for_mate_on_ubuntu()
{
    session="mate-session"
    selecttext="Select which user(s) to configure a MATE session for..."
    RequiredPackages=(mate-core mate-desktop-environment)
    
}

config_for_mate_on_mint()
{
    session="mate-session"
    selecttext="Select which user(s) to configure a MATE session for..."
    RequiredPackages=(mate-core mate-desktop-environment)
    
}

config_for_cinnamon()
{
	session="gnome-session --session cinnamon"
	selecttext="Select which user(s) to configure a Cinnamon session for..."
	RequiredPackages=(cinnamon cinnamon-common cinnamon-themes)
}

add_mate_repo_ubuntu()
{
    case $Dist in
        "Ubuntu 12.10"* )
            ( add-apt-repository -y "deb http://packages.mate-desktop.org/repo/ubuntu quantal main" && apt-get update && apt-get install -y --force-yes mate-archive-keyring && apt-get update ) 2>&1 | dialog --progressbox "Adding MATE repository for Ubuntu 12.10..." 90 70
            ;;
        "Ubuntu 12.04"* )
            ( add-apt-repository -y "deb http://packages.mate-desktop.org/repo/ubuntu precise main" && apt-get update && apt-get install -y --force-yes mate-archive-keyring && apt-get update ) 2>&1 | dialog --progressbox "Adding MATE repository for Ubuntu 12.04..." 90 70
            ;;
        "Ubuntu 11.10"* )
            ( add-apt-repository -y "deb http://packages.mate-desktop.org/repo/ubuntu oneiric main" && apt-get update && apt-get install -y --force-yes mate-archive-keyring && apt-get update ) 2>&1 | dialog --progressbox "Adding MATE repository for Ubuntu 11.10..." 90 70
            ;;
    esac
}

##########################################################
######## End of internal function declarations ###########
##########################################################

##############################################
######## Main routine starts here ############
##############################################

# Source the common functions...
DIALOG="dialog"

case "$supported" in
	"1")
		dialogtext="\nWelcome to the ScaryGliders RDPsesconfig script.\n\nThe detected distribution is : $Dist \non which this utility has been tested and supports.\n\nClick OK to continue...\n"
		info_window
		;;
	"0")
		dialogtext="\nWelcome to the ScaryGliders RDPsesconfig script.\n\nThe detected distribution is : $Dist .\n\nUnfortunately, no testing has been done for running this utility on this distribution.\n\nIf this is a Debian-based distro, you can try running it, but it might not work.\n\nIf the utility does work on this distribution, please let the author know!\n\nIf you wish to proceed, then click OK. Otherwise click Cancel to stop right here."
		info_window
		;;
esac

create_desktop_dialog_list
select_desktop

case "$desktop" in
	"Gnome Classic")
		config_for_gnome_classic
		;;
	"Unity-2D")
		config_for_unity2d
		;;
	"Xfce")
		config_for_xfce
		;;
	"KDE")
		config_for_kde
		;;
	"LXDE")
		config_for_lxde
		;;
	"Lubuntu")
		config_for_lubuntu
		;;
	"MATE")
	    case "$Dist" in
	        "Ubuntu 12.10"* | "Ubuntu 12.04"* | "Ubuntu 11.10"*)
	            add_mate_repo_ubuntu
	            config_for_mate_on_ubuntu
	            ;;
	        "Linux Mint"*)
		        config_for_mate_on_mint
		        ;;
        esac
    "Cinnamon")
		config_for_cinnamon
		;;
esac

install_required_packages # Check if packages for selected desktop are installed and install if not.	
select_local_user_accounts_to_config
create_xsession

dialogtext="\nAll selected operations are complete!\n\nThe users you configured will be able to log in via RDP now and be presented with the desktop you configured for them.\n\nIf you wish for RDP users to be able to perform certain tasks like \"local\" users, please see the configuration files located at /usr/share/polkit-1/actions/ .\n\nSee http://scarygliders.net for details on PolicyKit.\n\nClick OK to exit the utility.\n\n\nThank you for using the Scarygliders RDPsesconfig!\n"
info_window
