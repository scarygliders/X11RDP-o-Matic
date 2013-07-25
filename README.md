X11RDP-o-Matic
==============

What is it?
-----------
It's a suite of two tools...

X11RDP-o-matic.sh
-----------------
This bash script is a build tool. It will automatically compile,
install, and set up X11rdp and xrdp on your system.

X11rdp-o-matic.sh has a number of options configured by way of
command line switches...

Options
-------

  --help          : show this help.

  --justdoit      : perform a complete compile and install with sane defaults and no user interaction.
  
  --nocpuoptimize : do not change X11rdp build script to utilize more than 1 of your CPU cores.
  
  --nocleanup     : do not remove X11rdp / xrdp source code after installation. (Default is to clean up).
  
  --noinstall     : do not install anything, just build the packages
  
  --nox11rdp      : only build xrdp, without the x11rdp backend
  
  --bleeding-edge : clone from the neutrinolabs github source tree. Beware. Bleeding-edge might hurt :)

X11rdp-o-matic.sh has two modes of operation; interactive, and non-interactive...

Interactive mode is the default. It requires user input at run-time, and tries to walk the user through
the build process.

The script will run in non-interactive mode when you specify the --justdoit option. In this mode, the
script will choose sensible defaults and will require no user interaction. It will automatically detect
if you have more than 1 CPU core available and will utilze those extra cores in order to speed up
compilation of X11rdp. If you specify the --nocpuoptimze switch, then it will not utilize more than 1 core.

The --bleeding-edge switch will tell the tool to download the xrdp/x11rdp source from a different git repository,
and this is for highly experimental source code. You are advised to not use this switch unless you are a xrdp
developer. By default, the tool will use the normal FreeRDP git repository.

RDPsesconfig.sh
===============
This tool is an interactive utility. It configures the .xsession file for each selected user on your system and
with whatever desktop environment you've chosen for them.



Both utilities need to be run as root, so use su to get to your root prompt, or use sudo to start them

Please consider a donation if you found this useful :)

Full details at http://scarygliders.net/?p=1858
