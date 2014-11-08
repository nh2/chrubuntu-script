Script enable-hibernate:

#!/bin/bash
#http://askubuntu.com/a/94963/164341
cat << '_EOF_' |sudo tee /etc/polkit-1/localauthority/50-local.d/com.ubuntu.enable-hibernate.pkla
[Enable Hibernate]
Identity=unix-user:*
Action=org.freedesktop.upower.hibernate
ResultActive=yes
_EOF_
clear
echo
echo 'Hibernate enabled.'
echo

Script disable-suspend:

#!/bin/bash
#http://askubuntu.com/a/154821/164341
cat << '_EOF_' |sudo tee /etc/polkit-1/localauthority/50-local.d/com.ubuntu.disable-suspend.pkla
[Disable suspend by default]
Identity=unix-user:*
Action=org.freedesktop.upower.suspend
ResultActive=no
_EOF_
clear
echo
echo 'Suspend disabled.'
echo



For Ubuntu 14.04 with multiple users you´ll have to add this tags (so that is doesn´t depend of multiple-users or upower as manager instead of login1)

[Re-enable hibernate by default]
  Identity=unix-user:*
  Action=org.freedesktop.upower.hibernate
  ResultActive=yes

[Re-enable hibernate by default for login1]
  Identity=unix-user:*
  Action=org.freedesktop.login1.hibernate
  ResultActive=yes

[Re-enable hibernate for multiple users by default in logind]
  Identity=unix-user:*
  Action=org.freedesktop.login1.hibernate-multiple-sessions
  ResultActive=yes
