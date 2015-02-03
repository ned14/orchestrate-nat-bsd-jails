#!/bin/sh
# Create X NAT routed BSD jails
# (C) 2015 MaidSafe - Niall Douglas
# Created: Feb 2015

if [ "$(id -u)" != "0" ]; then
  >&2 echo "Need to run this script as root"
  exit 1
fi
if [ $# -eq 0 ]; then
  >&2 echo "Usage: $0 <no of jails>"
  exit 1
fi
TOTALJAILS=$1
if [ ! -e "/usr/jails/basejail" ]; then
  >&2 echo "I see no base jail install. Have you run 'ezjail-admin install' yet?"
  exit 1
fi

# First build a jail flavour giving us the config we want
rm -rf /usr/jails/flavours/make_natted_jails
cp -a /usr/jails/flavours/example /usr/jails/flavours/make_natted_jails
rm -rf /usr/jails/flavours/make_natted_jails/etc/rc.d/ezjail.flavour.example
cp /etc/resolv.conf /usr/jails/flavours/make_natted_jails/etc/resolv.conf
  
for N in $(seq 1 $TOTALJAILS)
do
  echo "Creating jail $N of $TOTALJAILS ..."
  JAILNAME=$(printf "lo7%03s" "$N")
  ifconfig $JAILNAME create
  ifconfig $JAILNAME inet 10.77.$N.1 netmask 255.255.255.0
  ezjail-admin create -f make_natted_jails $JAILNAME $JAILNAME\|10.77.$N.1 2> /dev/null
  
  # Copy files into /usr/jails/jail77N/root
  ezjail-admin start $JAILNAME
done

echo "Press Return to clean up ..."
read FOO

for N in $(seq 1 $TOTALJAILS)
do  
  echo "Deleting jail $N of $TOTALJAILS ..."
  JAILNAME=$(printf "lo7%03s" "$N")
  ezjail-admin stop $JAILNAME
  ezjail-admin delete $JAILNAME
  rm -rf /usr/jails/$JAILNAME
  ifconfig $JAILNAME destroy
done
