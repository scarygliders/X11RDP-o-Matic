export LANG="C"

#!/bin/bash
id=`id -u`
if [ $id -ne 0 ]
	then
			echo "\n\nPlease run as root.\n\n"
			exit 0
fi


echo Removing x11rdp and xrdp...

# remove source from /root directory
if [ -e /root/x11rdp_xorg71 ]
then
  rm -r /root/x11rdp_xorg71
fi

if [ -e /root/xrdp.git ]
then
  rm -r /root/xrdp.git
fi

#stop xrdp service
/etc/init.d/xrdp stop

# remove the startwm.sh symbolic link and restore original
rm /etc/xrdp/startwm.sh
mv /etc/xrdp/startwm.sh.BACKUP /etc/xrdp/startwm.sh

#remove the /opt/X11rdp tree
rm -r /opt/X11rdp/

#purge xrdp package
dpkg -P xrdp

#Remove the remaining dangling symbolic link
if [ -e /usr/bin/X11rdp ]
then
  rm /usr/bin/X11rdp
fi

#all done
echo Removal of xrdp/X11rdp complete.
