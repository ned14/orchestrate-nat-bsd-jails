#!/bin/sh -x
# Create X NAT routed BSD jails
# (C) 2015 MaidSafe - Niall Douglas
# Created: Feb 2015

if [ "$(id -u)" != "0" ]; then
  >&2 echo "ERROR: Need to run this script as root"
  exit 1
fi
if [ $# -lt 3 ]; then
  >&2 echo "Usage: $0 <no of jails> [Nat|Bridge] <cmd to run> [<directory to copy>]"
  exit 1
fi
TOTALJAILS=$1
case "$2" in
[Nn]*) NATORBRIDGE=1;;
*) NATORBRIDGE=0;;
esac
CMDTORUN=$3
if [ $# -gt 3 ]; then
  DIRTOCOPY=$4
else
  DIRTOCOPY=
fi
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

# First build a jail flavour giving us the config we want
rm -rf /usr/jails/flavours/make_natted_jails
cp -a /usr/jails/flavours/example /usr/jails/flavours/make_natted_jails
rm -rf /usr/jails/flavours/make_natted_jails/etc/rc.d/ezjail.flavour.example
cp /etc/resolv.conf /usr/jails/flavours/make_natted_jails/etc/resolv.conf
#echo 'sshd_enable="YES"' >> /usr/jails/flavours/make_natted_jails/etc/rc.conf

# Turn on IP forwarding
sysctl net.inet.ip.forwarding=1

# What is the IP of em0?
HOSTIPADDR=$(ifconfig em0 | grep "inet " | cut -f 2 -d ' ' -)

# Create a bridge for all the NAT jails to talk to one another
ifconfig bridge77 create
ifconfig bridge77 addm em0 up

EPAIRINDEX=1
for N in $(seq 1 $TOTALJAILS)
do
  echo "Creating jail $N of $TOTALJAILS ..."
  JAILNAME=$(printf "jail%03s" "$N")
  JAILEPAIRNAME=$(printf "epair%s" "$EPAIRINDEX")
  EPAIRINDEX=$(expr $EPAIRINDEX + 1)
  rm -rf /usr/jails/$JAILNAME
  # Create a virtual ethernet patch cable (I joke not ...)
  ifconfig $JAILEPAIRNAME create up
  # That creates two if devices, epair$Na for the host side and epair$Nb for the jail side
  # Create the jail from my flavour
  ezjail-admin create -f make_natted_jails $JAILNAME x 2> /dev/null
  # Enable own network stack for the jail
  echo "export jail_${JAILNAME}_parameters=\"vnet vnet.interface=${JAILEPAIRNAME}b allow.raw_sockets\"" >> /usr/local/etc/ezjail/$JAILNAME
  
  # Copy files into /usr/jails/jail77N/root
  #cp -a runonboot /usr/jails/$JAILNAME/etc/rc.d/runonboot
  echo "firewall_enable=\"YES\"" >> /usr/jails/$JAILNAME/etc/rc.conf
  echo "firewall_script=\"/etc/rc.firewall\"" >> /usr/jails/$JAILNAME/etc/rc.conf
  echo "firewall_type=\"OPEN\"" >> /usr/jails/$JAILNAME/etc/rc.conf
  echo "gateway_enable=\"YES\"" >> /usr/jails/$JAILNAME/etc/rc.conf
  
  if [ -n "$DIRTOCOPY" ]; then
    cp -r "$DIRTOCOPY" /tmp/
  fi
  
  # Start the jail
  ezjail-admin start $JAILNAME
  
  if [ "$NATORBRIDGE" -eq 0 ]; then
  
    LOCALIPINDEX=$(expr $N + 77)
    jexec $JAILNAME /sbin/ifconfig ${JAILEPAIRNAME}b inet 192.168.2.$LOCALIPINDEX netmask 255.255.255.0 up
    jexec $JAILNAME /sbin/route add default 192.168.2.1
    ifconfig bridge77 addm ${JAILEPAIRNAME}a up

  else
  
    # Configure the network stack for the jail, default routing to .254
    jexec $JAILNAME /sbin/ifconfig ${JAILEPAIRNAME}b inet 10.77.$N.1 netmask 255.255.255.0 up
    jexec $JAILNAME /sbin/route add default 10.77.$N.254
    
    echo "Creating natjail $N of $TOTALJAILS ..."
    JAILNAME=$(printf "natjail%03s" "$N")
    NATJAILEPAIRNAME=$(printf "epair%s" "$EPAIRINDEX")
    EPAIRINDEX=$(expr $EPAIRINDEX + 1)
    rm -rf /usr/jails/$JAILNAME
    ifconfig $NATJAILEPAIRNAME create up
    ezjail-admin create -f make_natted_jails $JAILNAME x 2> /dev/null
    # Enable own network stack for the jail, patching the network from the earlier jail into this one
    echo "export jail_${JAILNAME}_parameters=\"vnet vnet.interface=${NATJAILEPAIRNAME}b allow.raw_sockets\"" >> /usr/local/etc/ezjail/$JAILNAME

    # Have the NAT jail gets its public IP via DHCP from whoever provides the host DHCP
  ##  echo "network_interfaces=\"${NATJAILEPAIRNAME}b\"" >> /usr/jails/$JAILNAME/etc/rc.conf
  ##  echo "ifconfig_${NATJAILEPAIRNAME}b=\"DHCP\"" >> /usr/jails/$JAILNAME/etc/rc.conf
    echo "firewall_enable=\"YES\"" >> /usr/jails/$JAILNAME/etc/rc.conf
    echo "firewall_script=\"/etc/rc.firewall\"" >> /usr/jails/$JAILNAME/etc/rc.conf
    echo "firewall_type=\"OPEN\"" >> /usr/jails/$JAILNAME/etc/rc.conf
    echo "gateway_enable=\"YES\"" >> /usr/jails/$JAILNAME/etc/rc.conf
  #  echo "firewall_nat_enable=\"YES\"" >> /usr/jails/$JAILNAME/etc/rc.conf
  #  echo "firewall_nat_interface=\"${NATJAILEPAIRNAME}b\"" >> /usr/jails/$JAILNAME/etc/rc.conf
  #  echo "firewall_nat_flags=\"same_ports reset\"" >> /usr/jails/$JAILNAME/etc/rc.conf
    echo "natd_enable=\"YES\"" >> /usr/jails/$JAILNAME/etc/rc.conf
    echo "natd_interface=\"${NATJAILEPAIRNAME}b\"" >> /usr/jails/$JAILNAME/etc/rc.conf
    ifconfig bridge77 addm ${NATJAILEPAIRNAME}a up
    
    # Start the jail
    ezjail-admin start $JAILNAME
    LOCALIPINDEX=$(expr $N + 77)
    jexec $JAILNAME /sbin/ifconfig ${NATJAILEPAIRNAME}b inet 192.168.2.$LOCALIPINDEX netmask 255.255.255.0 up
    jexec $JAILNAME /sbin/route add default 192.168.2.1
    
    # Attach the other end of the earlier jail to natjail with its default routed .254
    ifconfig ${JAILEPAIRNAME}a vnet $JAILNAME
    jexec $JAILNAME /sbin/ifconfig ${JAILEPAIRNAME}a inet 10.77.$N.254 netmask 255.255.255.0 up
    
    # Start natd
    jexec $JAILNAME /usr/sbin/service natd start
    
  fi

  # Check the NAT jail routing table
  jexec $JAILNAME /usr/bin/netstat -r
  
  JAILNAME=$(printf "jail%03s" "$N")
  DIRLEAF=$(basename "$DIRTOCOPY")
  if [ -n "$SUDO_USER" ]; then
    jexec -u $SUDO_USER $JAILNAME "cd /tmp/${DIRLEAF} && $CMDTORUN >& /tmp/cmdlog"
  else
    jexec $JAILNAME "cd /tmp/${DIRLEAF} && $CMDTORUN >& /tmp/cmdlog"
  fi
done

echo "$TOTALJAILS NATed jails are now running command $CMDTORUN under user $SUDO_USER:"
jls
