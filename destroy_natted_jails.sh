#!/bin/sh
# Destroy X NAT routed BSD jails
# (C) 2015 MaidSafe - Niall Douglas
# Created: Feb 2015

if [ "$(id -u)" != "0" ]; then
  >&2 echo "ERROR: Need to run this script as root"
  exit 1
fi
if [ $# -eq 0 ]; then
  >&2 echo "Usage: $0 <no of jails>"
  exit 1
fi
TOTALJAILS=$1
if [ ! -e "/usr/jails/basejail" ]; then
  >&2 echo "ERROR: I see no base jail install. Have you run 'ezjail-admin install' yet?"
  exit 1
fi
VIMAGE_IN_KERNEL=$(dmesg | grep VIMAGE)
if [ -z "$VIMAGE_IN_KERNEL" ]; then
  >&2 echo "ERROR: This kernel appears to not have been built with networking stack virtualisation (VIMAGE)"
  exit 1
fi
IPDIVERT_IN_KERNEL=$(strings /boot/kernel/kernel | grep IPDIVERT)
if [ -z "$IPDIVERT_IN_KERNEL" ]; then
  >&2 echo "ERROR: This kernel appears to not have been built with IP divert enabled (IPDIVERT)"
  exit 1
fi


EPAIRINDEX=1
for N in $(seq 1 $TOTALJAILS)
do  
  echo "Deleting jail $N of $TOTALJAILS ..."
  JAILNAME=$(printf "jail%03s" "$N")
  JAILEPAIRNAME=$(printf "epair%s" "$EPAIRINDEX")
  EPAIRINDEX=$(expr $EPAIRINDEX + 1)
  echo "Process output log was:"
  jexec $JAILNAME /bin/cat /tmp/cmdlog
  ezjail-admin stop $JAILNAME
  ezjail-admin delete $JAILNAME
  rm -rf /usr/jails/$JAILNAME
  ifconfig ${JAILEPAIRNAME}a destroy || true

  echo "Deleting natjail $N of $TOTALJAILS ..."
  JAILNAME=$(printf "natjail%03s" "$N")
  NATJAILEPAIRNAME=$(printf "epair%s" "$EPAIRINDEX")
  EPAIRINDEX=$(expr $EPAIRINDEX + 1)
  ezjail-admin stop $JAILNAME || true
  ezjail-admin delete $JAILNAME || true
  rm -rf /usr/jails/$JAILNAME

  ifconfig ${JAILEPAIRNAME}a destroy
  ifconfig bridge77 deletem ${JAILEPAIRNAME}a up || true
  ifconfig bridge77 deletem ${NATJAILEPAIRNAME}a up || true
  ifconfig ${NATJAILEPAIRNAME}a destroy || true
done

# Destroy the NAT bridge
ifconfig bridge77 deletem em0
ifconfig bridge77 destroy
