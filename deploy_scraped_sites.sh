#!/bin/bash
clear
### Cobalt Strike variables
CSURL="https://download.cobaltstrike.com"

### User Customization Variables
# Proxy settings for the Range.
ProxyIP="172.30.0.2"
ProxySub="21"
ProxyNetID="172.30.0.0"
ProxyPort="9999"

# Root password
MasterRootPass="toor"

# Certificate Authority Variables
CA="globalcert.com"
cac="US"                   # Country for cert
cast="Oregon"              # State for cert
cal="Seattle"              # Locality (city)
cao="Global Certificates, Inc"  # Organization
caou="Root Cert"           # Organizational unit
capempass="password"

#### End of User Customization Section

Proxy="http://$ProxyIP:$ProxyPort"
CAPass=$MasterRootPass
DNSPass=$MasterRootPass
SIPass=$MasterRootPass

# Network Interfaces for various builds.
# IA Proxy IP settings
iapnic1="$ProxyIP/$ProxySub"
iapnic2="dhcp"

# Root DNS IP Settings
rootdnsnic1="dhcp"
rootdnsnic2="8.8.8.8/24
             198.41.0.4/24  
             199.9.14.201/24 
             192.33.4.12/24 
             199.7.91.13/24 
             192.203.230.10/24 
             195.5.5.241/24 
             192.112.36.4/24
             198.97.190.53/24 
             192.36.148.17/24 
             192.58.128.30/24 
             193.0.14.129/24 
             199.7.83.42/24 
             202.12.27.33/24"
rootdnsgw="8.8.8.1"

# CA Server
canic1="dhcp"
canic2="180.1.1.50/24"
caip="180.1.1.50"
cagw="180.1.1.1"

# RTS
rtsnic1="dhcp"
oct3=$(shuf -i 0-15 -n 1)
oct4=$(shuf -i 2-254 -n 1)
rtsnic2="5.29.$oct3.$oct4/20"
rtsgw="5.29.0.1"

# Web Servers
webnic1="dhcp"
webnic2="180.1.1.100/24
        180.1.1.110/24
        180.1.1.120/24
        180.1.1.130/24
        180.1.1.140/24
        180.1.1.150/24"
webgw="180.1.1.1"
owncloudIP="180.1.1.100"
pastebinIP="180.1.1.110"
redbookIP="180.1.1.120"
drawioIP="180.1.1.130"
ntpIP="180.1.1.140"
mssitesIP="180.1.1.150"

# Traffic Gen
trafnic1="dhcp"
trafnic2="92.107.127.12/24
          72.32.4.26/24
          67.23.44.93/24
          70.32.91.153/24
          188.65.120.83/24"
trafgw="92.107.127.1"

# Web Host (Traffic WebHost)
webhostnic1="dhcp"
webhostnic2="92.107.127.100/24"
webhostgw="92.107.127.1"

# Color codes for output
white="\e[1;37m"
ltblue="\e[1;36m"
red="\e[1;31m"
green="\e[1;32m"
yellow="\e[1;32m"
default="\e[0m"

# Determine primary (anic) and secondary (gnic) network interfaces.
anic=$(ip link show | grep ^2: | awk '{print $2}' | cut -d: -f1)
if [ -z "$anic" ]; then
  echo -e "$red Error: Could not determine your first NIC.$default"
  exit 1
fi
gnic=$(ip link show | grep ^3: | awk '{print $2}' | cut -d: -f1)
if [ -z "$gnic" ]; then
  echo -e "$red Error: Second NIC not detected. Ensure you have added one for this VM.$default"
  exit 1
fi

# Archive name – assume the tarball (trafficsites.tar.gz) is pre-generated and in the current directory.
ARCHIVE="trafficsites.tar.gz"
if [ ! -f "$ARCHIVE" ]; then
  echo -e "$red Archive $ARCHIVE not found!$default"
  exit 1
fi

### Begin Traffic WebHost Deployment (Option 7 Only)
clear
echo -e "$green Setting up Traffic Web Host server $default"
sleep 2

# Copy any additional files from WebHost folder (if needed)
[ -d "WebHost" ] && cp -r WebHost/* /root/

# Update package lists and install required packages.
apt update
apt install -y apache2 python3-pip
# (No gdown here because the tarball is already provided.)
a2enmod ssl

echo -e "$green Extracting sites from archive. $default"
sleep 2
tar -zxvf "$ARCHIVE" -C /var/www/html
rm -f /var/www/html/index.html
mv /var/www/html/websites.txt /tmp/

# Generate SSH keys if they do not exist and copy key to CA server.
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -b 1024 -t rsa -f /root/.ssh/id_rsa -q -N ""
fi
sshpass -p "$CAPass" ssh-copy-id -o StrictHostKeyChecking=no root@180.1.1.50

# -------------------------------
# Set Up Basic Networking
# -------------------------------
echo -e "auto lo\niface lo inet loopback\n\nauto $anic\niface $anic inet dhcp" > /etc/network/interfaces

# Assume that websites.txt already contains pre‑resolved domain,IP pairs.
# Separate the list into routes, ips, and domains.
routes=$(cut -d, -f2 /tmp/websites.txt | cut -d. -f1-3 | sort -t . -k1,1n -k2,2n -k3,3n | uniq)
ips=$(cut -d, -f2 /tmp/websites.txt | sort -t . -k1,1n -k2,2n -k3,3n -k4,4n | uniq)
domains=$(cut -d, -f1 /tmp/websites.txt | sort | uniq)

echo -e "$green Configuring static IPs on secondary NIC ($gnic). $default"
count=0
cidr=24
for ip in $ips; do
    if [[ $count == 0 ]]; then
        echo -e "\nauto $gnic\niface $gnic inet static\n\taddress $ip/$cidr" >> /etc/network/interfaces
        first3octets=$(echo $ip | cut -d. -f1,2,3)
        gw="$first3octets.1"
        echo -e "\tgateway $gw" >> /etc/network/interfaces
        count=1
    else
        echo -e "\nauto $gnic:$count\niface $gnic:$count inet static\n\taddress $ip/$cidr" >> /etc/network/interfaces
        count=$((count+1))
    fi
done

# -------------------------------
# Build SI-Router Routes Script
# -------------------------------
echo -e "$green Configuring routes for the SI_router. $default"
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
sshpass -p "$SIPass" scp -o StrictHostKeyChecking=no "$SI_SCRIPT" vyos@172.30.7.254:/home/vyos/Scripts/
sshpass -p "$SIPass" ssh -o StrictHostKeyChecking=no vyos@172.30.7.254 '/home/vyos/Scripts/Eth1TrafficWebHosts.sh'

# -------------------------------
# Configure Apache Virtual Hosts and Generate SSL Certificates
# -------------------------------
echo -e "$green Configuring Apache Web server and generating SSL certificates via the CA-Server. $default"
httpconf="TG_HTTP.conf"
httpsconf="TG_HTTPS.conf"
> $httpconf
> $httpsconf
for domain in $domains; do 
    tld=$(echo "$domain" | sed 's/www.//g')
    # HTTP configuration.
    echo "<VirtualHost *:80>" >> $httpconf
    echo "    ServerAdmin webmaster@$tld" >> $httpconf
    echo "    ServerName $tld" >> $httpconf
    echo "    ServerAlias www.$tld" >> $httpconf
    echo "    DocumentRoot /var/www/html/$tld" >> $httpconf
    echo "    ErrorLog \${APACHE_LOG_DIR}/error.log" >> $httpconf
    echo "    CustomLog \${APACHE_LOG_DIR}/access.log combined" >> $httpconf
    echo "</VirtualHost>" >> $httpconf
    # HTTPS configuration.
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
    # Generate SSL Cert for the domain (using the CA server) as in the original script.
    sshpass -p "$CAPass" ssh root@180.1.1.50 "/root/scripts/certmaker.sh -d $tld -q -r"
    sshpass -p "$CAPass" scp root@180.1.1.50:/var/www/html/$tld.crt /etc/ssl/certs/
    sshpass -p "$CAPass" scp root@180.1.1.50:/var/www/html/$tld.key /etc/ssl/private/
done
mv $httpconf /etc/apache2/sites-available/
mv $httpsconf /etc/apache2/sites-available/
a2ensite $httpconf
a2ensite $httpsconf

# -------------------------------
# Restart Networking and Apache
# -------------------------------
ip addr flush $anic
ip addr flush $gnic
service networking restart
systemctl reload apache2

clear
echo -e "$green Registering domains on RootDNS server. $default"
sshpass -p "$DNSPass" scp -o StrictHostKeyChecking=no /tmp/websites.txt 198.41.0.4:/root/scripts/
sshpass -p "$DNSPass" ssh -o StrictHostKeyChecking=no 198.41.0.4 '/root/scripts/add-TRAFFIC-DNS.sh /root/scripts/websites.txt'

clear
echo -e "$green Setting up SSL cert renewal automation Cron job $default"
crontab -l > cronjbs
echo "0 2 * * * /root/scripts/SSLcheck.sh" >> cronjbs
crontab cronjbs

echo -e "$green Installation Complete! $default"
