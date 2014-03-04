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

  --help             : show this help.

  --justdoit         : perform a complete compile and install with sane defaults and no user interaction.

  --branch <branch>  : use one of the available xrdp branches

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

X11rdp-o-matic.sh has two modes of operation; interactive, and non-interactive...

Interactive mode is the default. It requires user input at run-time, and tries to walk the user through
the build process.

The script will run in non-interactive mode when you specify the --justdoit option. In this mode, the
script will choose sensible defaults and will require no user interaction. It will automatically detect
if you have more than 1 CPU core available and will utilze those extra cores in order to speed up
compilation of X11rdp. If you specify the --nocpuoptimze switch, then it will not utilize more than 1 core.

The --bleeding-edge switch will tell the tool to download the xrdp/x11rdp source from the DEVEL git repository,
and this is for source code in the development branch. You are advised to not use this switch unless you are a xrdp
developer. By default, the tool will use the normal Neutrinolabs master repository.

RDPsesconfig.sh
===============
This tool is an interactive utility. It configures the .xsession file for each selected user on your system and
with whatever desktop environment you've chosen for them.



Both utilities need to be run as root, so use su to get to your root prompt, or use sudo to start them

Please consider a donation if you found this useful :)

Full details at http://scarygliders.net/x11rdp-o-matic-information/
