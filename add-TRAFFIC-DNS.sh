#!/bin/bash
# Written by Chip McElvain 
# Script to add DNS records.
# Needs a file to read in.
# Format for the file should be domain,IP 

# Prevent a PID to lock the script to prevent simultaneous execution.
PIDFILE="/root/scripts/addDNS.pid"

# Check if the script is already running before doing things.
if [[ -s $PIDFILE ]]; then
  echo "Script is currently running, try again later"
  exit 0
else
  echo $BASHPID > $PIDFILE
fi 

# Check for argument.
if [ -z "$1" ]
then
  echo "This script requires a file to be passed as an argument"
  echo "The file format is domain,IP"
  rm $PIDFILE
  exit 1
else
  dnsconf=$1
fi

# Clear terminal for output.
clear

# Check to see if dnsconf file exists and isn't empty.
if [ ! -f $dnsconf ] || [ ! -s $dnsconf ]
then
  echo "The file $dnsconf is empty or doesn't exist."
  echo "Script is exiting"
  rm $PIDFILE
  exit 1
fi

# Set variables.
bdir="/etc/bind"
odir="/etc/bind/TRAFFIC"
sdir="/root/scripts"

# A DNS file exists and isn't empty, so we are going to process it.
echo "DNS file processing."

# Create comment tags for DNS entries based on what was passed in the tag line.
# Otherwise use a generic OPFOR tag.  This is used to remove DNS entries later.
# NOTE: for a zone file comments are denoted by a ";"
# NOTE: for zone references made in named.conf, comments are denoted by "//".
zonetag=";Traffic-Website"
namedstart="//Traffic websites START"
namedend="//Traffic websites END"

# Create a zones.tmp file for storing zone references that we will add
# to the named.conf at the end.
echo $namedstart > $sdir/zones.tmp

# Loop through the DNS file records in $dnsconf.
while read i; do
  # Ignore comments and empty lines.
  if [[ $i == \#* ]] || [[ $i == "" ]]; then
    continue
  fi

  # Separate domain and IP.
  domain=$(echo $i | cut -d, -f1)
  IP=$(echo $i | cut -d, -f2)

  # Create zone file or overwrite any existing zone files with the same domain.
  # First check to see if a zone file for the domain exists using a wildcard
  # for directories so it will check OPFOR, SimSpace, and Range directories.
  if [ -f /etc/bind/*/db.$domain ]; then
    # If we get a hit, we'll see if it's already an OPFOR domain and update it.
    if [ -f $odir/db.$domain ]; then
      echo "Updating db.$domain"
    else 
      echo "Domain $domain is already registered. Skipping"
      continue
    fi
  else
    echo "Adding db.$domain"
  fi

  # Create the zone file.
  echo "$zonetag" > $odir/db.$domain
  echo -e "\$TTL\t86400" >> $odir/db.$domain
  echo -e "@\tIN\tSOA\t@\tns1.$domain. 42 3H 15M 1W 1D" >> $odir/db.$domain
  echo -e "@\tIN\tNS\t\tns1.$domain." >> $odir/db.$domain
  echo -e "@\tIN\tMX\t10\t$domain." >> $odir/db.$domain
  echo -e "@\tIN\tA\t\t$IP" >> $odir/db.$domain
  echo -e "mail\tIN\tA\t\t$IP" >> $odir/db.$domain
  echo -e "www\tIN\tA\t\t$IP" >> $odir/db.$domain
  echo -e "ns1\tIN\tA\t\t198.41.0.4" >> $odir/db.$domain

  # Check if domain is already in named.conf.TRAFFIC or already added in zones.tmp.
  if grep -Fq "zone \"$domain.\"" $bdir/named.conf.TRAFFIC || grep -Fq "zone \"$domain.\"" $sdir/zones.tmp; then
    continue  # We don't need to add the reference since it already exists.
  else
    # Create zone file reference in the temporary zones file.
    echo "zone \"$domain.\" IN {"  >> $sdir/zones.tmp
    echo "    type master;" >> $sdir/zones.tmp
    echo "    file \"TRAFFIC/db.$domain\";" >> $sdir/zones.tmp
    echo "    allow-query { any; };" >> $sdir/zones.tmp
    echo "    allow-update { none; };" >> $sdir/zones.tmp
    echo "};" >> $sdir/zones.tmp
  fi
done < $dnsconf

# Check to see if there were any zone file references that need to be added to named.conf.
if [[ $(wc -l < $sdir/zones.tmp) -eq 1 ]]; then
  echo "No new zone files to add to named.conf"
  rm $sdir/zones.tmp
else
  # Close the zone reference file with a tag so the section can be identified.
  echo $namedend >> $sdir/zones.tmp
  cat $sdir/zones.tmp $bdir/named.conf.TRAFFIC > $sdir/named.tmp

  # Check the modified named.conf configuration.
  if /usr/bin/named-checkconf $sdir/named.tmp > /dev/null 2>&1; then
    echo "DNS Zone changes to named.conf checked out good"
    rm $sdir/zones.tmp
    mv $sdir/named.tmp $bdir/named.conf.TRAFFIC
  else
    echo "DNS Zone changes created errors, see below"
    /usr/bin/named-checkconf $sdir/named.tmp
    rm $sdir/named.tmp
    rm $sdir/zones.tmp
    rm $PIDFILE
    exit 1
  fi
fi

# If the script is still running, config changes are good so let's restart bind9 on the root server.
echo "Restarting bind9 service"
service bind9 restart
echo "Bind9 Status is below"
bindstatus=$(service bind9 status | grep Active)
if service bind9 status | grep -q "running"; then
  echo "bind9 is good, have a good day!"
else
  echo "Bind9 has a problem, WHAT DID YOU DO!!"
  /usr/bin/named-checkconf $bdir/named.conf.TRAFFIC
  rm $PIDFILE
  exit 1
fi
rm $PIDFILE
