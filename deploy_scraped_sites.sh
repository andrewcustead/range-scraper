#!/bin/bash
# This script is to be run on the VM that does NOT have Internet access.
# It expects the tarball (trafficsites.tar.gz) produced by the scrape script to be present locally.
# It extracts the archive into /var/www/html and then continues with the remaining configuration:
# - Removing the default index file
# - Moving websites.txt for processing
# - Copying any additional files (e.g., WebHost/ if available)
# - Generating SSH keys, setting up networking, Apache virtual hosts, SSL certificate generation, etc.
#
# Adjust the variables (CAPass, SIPass, DNSPass, anic, gnic) as needed.
#
# Usage: ./deploy_scraped_sites.sh

# === CONFIGURATION VARIABLES ===
CAPass="YourCAPassword"       # CA server password
SIPass="YourSIPassword"       # SI router password
DNSPass="YourDNSPassword"     # DNS server password
anic="your_anic_interface"    # e.g., eth0
gnic="your_gnic_interface"    # e.g., eth1

ARCHIVE="trafficsites.tar.gz"

# Check if the archive exists
if [ ! -f "$ARCHIVE" ]; then
  echo "Archive $ARCHIVE not found!"
  exit 1
fi

echo "Extracting archive to /var/www/html ..."
tar -xzvf "$ARCHIVE" -C /var/www/html

# Remove the default index file if it exists
rm -f /var/www/html/index.html

# Move the websites.txt file to /tmp for further processing
mv /var/www/html/websites.txt /tmp/

# If a WebHost folder is present locally (for additional configuration), copy its contents to /root/
if [ -d "WebHost" ]; then
  cp -r WebHost/* /root/
fi

# Generate SSH keys (if not already present) and copy the public key to the CA server
ssh-keygen -b 1024 -t rsa -f /root/.ssh/id_rsa -q -N ""
sshpass -p "$CAPass" ssh-copy-id -o StrictHostKeyChecking=no root@180.1.1.50

# Configure the base networking settings
echo -e "auto lo\niface lo inet loopback\n\nauto $anic\niface $anic inet dhcp" > /etc/network/interfaces

# Process the websites.txt file to separate domains, IPs, and create route information
routes=$(cut -d, -f2 /tmp/websites.txt | cut -d. -f1-3 | sort -t . -k1,1n -k2,2n -k3,3n | uniq)
ips=$(cut -d, -f2 /tmp/websites.txt | sort -t . -k1,1n -k2,2n -k3,3n -k4,4n | uniq)
domains=$(cut -d, -f1 /tmp/websites.txt | sort | uniq)

echo "Configuring IPs in /etc/network/interfaces..."
count=0
cidr=24
for ip in $ips; do
  if [ "$count" -eq 0 ]; then
    echo -e "\nauto $gnic\niface $gnic inet static\n\taddress $ip/$cidr" >> /etc/network/interfaces
    first3octets=$(echo $ip | cut -d. -f1,2,3)
    gw="$first3octets.1"
    echo -e "\tgateway $gw" >> /etc/network/interfaces
    count=1
  else
    echo -e "\nauto $gnic:$count\niface $gnic:$count inet static\n\taddress $ip/$cidr" >> /etc/network/interfaces
    count=$((count + 1))
  fi
done

# Build a script for configuring routes on the SI_router using the collected route info
echo "Configuring routes for the SI_router..."
SI_SCRIPT="/tmp/Eth1TrafficWebHosts.sh"
echo "#!/bin/vbash" > "$SI_SCRIPT"
echo "source /opt/vyatta/etc/functions/script-template" >> "$SI_SCRIPT"
echo "configure" >> "$SI_SCRIPT"
chmod 755 "$SI_SCRIPT"
for subnet in $routes; do
  echo "set interfaces ethernet eth1 address $subnet.1/24" >> "$SI_SCRIPT"
done
echo "commit" >> "$SI_SCRIPT"
echo "save" >> "$SI_SCRIPT"
echo "exit" >> "$SI_SCRIPT"

# Copy the route configuration script to the SI_router and execute it
sshpass -p "$SIPass" scp -o StrictHostKeyChecking=no "$SI_SCRIPT" vyos@172.30.7.254:/home/vyos/Scripts/
sshpass -p "$SIPass" ssh -o StrictHostKeyChecking=no vyos@172.30.7.254 '/home/vyos/Scripts/Eth1TrafficWebHosts.sh'

# Configure Apache virtual hosts and generate SSL certificates via the CA-Server
echo "Configuring Apache and generating SSL certificates..."
httpconf="TG_HTTP.conf"
httpsconf="TG_HTTPS.conf"
> $httpconf
> $httpsconf
for domain in $domains; do
  tld=$(echo "$domain" | sed 's/www.//g')
  # HTTP configuration
  echo "<VirtualHost *:80>" >> $httpconf
  echo "    ServerAdmin webmaster@$tld" >> $httpconf
  echo "    ServerName $tld" >> $httpconf
  echo "    ServerAlias www.$tld" >> $httpconf
  echo "    DocumentRoot /var/www/html/$tld" >> $httpconf
  echo "    ErrorLog \${APACHE_LOG_DIR}/error.log" >> $httpconf
  echo "    CustomLog \${APACHE_LOG_DIR}/access.log combined" >> $httpconf
  echo "</VirtualHost>" >> $httpconf

  # HTTPS configuration
  echo "<VirtualHost *:443>" >> $httpsconf
  echo "    ServerName \"$tld\"" >> $httpsconf
  echo "    ServerAlias \"www.$tld\"" >> $httpsconf
  echo "    ServerAdmin webmaster@$tld" >> $httpsconf
  echo "    DocumentRoot /var/www/html/$tld" >> $httpsconf
  echo "    ErrorLog \${APACHE_LOG_DIR}/error.log" >> $httpsconf
  echo "    CustomLog \${APACHE_LOG_DIR}/access.log combined" >> $httpsconf
  echo "    SSLEngine on" >> $httpsconf
  echo "    SSLCertificateFile /etc/ssl/certs/$tld.crt" >> $httpsconf
  echo "    SSLCertificateKeyFile /etc/ssl/private/$tld.key" >> $httpsconf
  echo "</VirtualHost>" >> $httpsconf

  # Generate and fetch SSL certificates via the CA server
  sshpass -p "$CAPass" ssh root@180.1.1.50 "/root/scripts/certmaker.sh -d $tld -q -r"
  sshpass -p "$CAPass" scp root@180.1.1.50:/var/www/html/$tld.crt /etc/ssl/certs/
  sshpass -p "$CAPass" scp root@180.1.1.50:/var/www/html/$tld.key /etc/ssl/private/
done

mv $httpconf /etc/apache2/sites-available/
mv $httpsconf /etc/apache2/sites-available/
a2ensite $httpconf
a2ensite $httpsconf

# Flush IP addresses and restart networking
ip addr flush $anic
ip addr flush $gnic
service networking restart
systemctl reload apache2

clear
echo "Registering domains on RootDNS server..."
sshpass -p "$DNSPass" scp -o StrictHostKeyChecking=no /tmp/websites.txt 198.41.0.4:/root/scripts/
sshpass -p "$DNSPass" ssh -o StrictHostKeyChecking=no 198.41.0.4 '/root/scripts/add-TRAFFIC-DNS.sh /root/scripts/websites.txt'

clear
echo "Setting up SSL certificate renewal automation Cron job..."
crontab -l > cronjbs
echo "0 2 * * * /root/scripts/SSLcheck.sh" >> cronjbs
crontab cronjbs

echo "Installation Complete!"
