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
echo 'sshd_enable="YES"' >> /usr/jails/flavours/make_natted_jails/etc/rc.conf

# Turn on IP forwarding
sysctl net.inet.ip.forwarding=1

# What is the IP of em0?
HOSTIPADDR=$(ifconfig em0 | grep "inet " | cut -f 2 -d ' ' -)

echo 'include "/etc/pf.conf"' > pf.conf
for N in $(seq 1 $TOTALJAILS)
do
  echo "Configuring simulated network stack $N of $TOTALJAILS ..."
  JAILNAME=$(printf "lo7%03s" "$N")
  rm -rf /usr/jails/$JAILNAME
  # Create a custom loopback device for the jail
  ifconfig $JAILNAME create
  ifconfig $JAILNAME inet 10.77.$N.1 netmask 255.255.255.0
  # Configure a nat on custom loopback device
  echo "nat pass on em0 from 10.77.$N.1 to any -> $HOSTIPADDR" >> pf.conf
done
pfctl -f pf.conf

for N in $(seq 1 $TOTALJAILS)
do
  echo "Creating jail $N of $TOTALJAILS ..."
  JAILNAME=$(printf "lo7%03s" "$N")
  # Create the jail from my flavour
  ezjail-admin create -f make_natted_jails $JAILNAME $JAILNAME\|10.77.$N.1 2> /dev/null
  # Enable raw sockets for the jail
  echo "export jail_${JAILNAME}_parameters=\"allow.raw_sockets\"" >> /usr/local/etc/ezjail/$JAILNAME
  
  # Copy files into /usr/jails/jail77N/root
  cp -a runonboot /usr/jails/$JAILNAME/etc/rc.d/runonboot
  
  # Start the jail
  ezjail-admin start $JAILNAME
done

echo "Press Return to clean up ..."
read FOO

for N in $(seq 1 $TOTALJAILS)
do  
  echo "Deleting jail $N of $TOTALJAILS ..."
  JAILNAME=$(printf "lo7%03s" "$N")
  echo "Ping log was:"
  jexec $JAILNAME /usr/bin/killall ping
  jexec $JAILNAME /bin/cat /root/pinglog
  ezjail-admin stop $JAILNAME
  ezjail-admin delete $JAILNAME
  rm -rf /usr/jails/$JAILNAME
  ifconfig $JAILNAME destroy
done
# Flush the NAT table entries
pfctl -F nat
