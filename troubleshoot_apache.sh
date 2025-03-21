#!/bin/bash
# troubleshoot_apache.sh
#
# This script performs several Apache troubleshooting steps based on the
# domains listed in websites.txt (format: domain,IP).
#
# It will:
#  1. Check if the SSL certificate (/etc/ssl/certs/<domain>.crt) and key
#     (/etc/ssl/private/<domain>.key) exist and are non-empty.
#  2. Check if the DocumentRoot directory (/var/www/html/<domain>) exists.
#  3. Output the last 50 lines of the Apache error log.
#  4. Check for port conflicts on ports 80 and 443.
#  5. Run apache2ctl configtest.
#
# Usage: sudo ./troubleshoot_apache.sh websites.txt

INPUT_FILE="websites.txt"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: $INPUT_FILE not found."
    exit 1
fi

echo "Starting Apache troubleshooting using $INPUT_FILE..."
echo "----------------------------------------"
echo ""

### Step 1: Check SSL certificate files for each domain.
echo "Step 1: Checking SSL certificate and key files..."
while IFS=, read -r domain ip; do
    domain=$(echo "$domain" | xargs)
    # Skip empty lines.
    [ -z "$domain" ] && continue

    cert_file="/etc/ssl/certs/${domain}.crt"
    key_file="/etc/ssl/private/${domain}.key"

    if [ ! -f "$cert_file" ]; then
        echo "Missing certificate file for $domain: $cert_file not found."
    else
        if [ ! -s "$cert_file" ]; then
            echo "Certificate file for $domain is empty: $cert_file"
        fi
    fi

    if [ ! -f "$key_file" ]; then
        echo "Missing key file for $domain: $key_file not found."
    else
        if [ ! -s "$key_file" ]; then
            echo "Key file for $domain is empty: $key_file"
        fi
    fi
done < "$INPUT_FILE"
echo ""

### Step 2: Check DocumentRoot directories.
echo "Step 2: Checking DocumentRoot directories..."
while IFS=, read -r domain ip; do
    domain=$(echo "$domain" | xargs)
    [ -z "$domain" ] && continue

    docroot="/var/www/html/${domain}"
    if [ ! -d "$docroot" ]; then
        echo "Missing DocumentRoot for $domain: Directory $docroot does not exist."
    fi
done < "$INPUT_FILE"
echo ""

### Step 3: Output Apache error log tail.
echo "Step 3: Displaying the last 50 lines of Apache's error log:"
sudo tail -n 50 /var/log/apache2/error.log
echo ""

### Step 4: Check for port conflicts on ports 80 and 443.
echo "Step 4: Checking for processes using port 80:"
sudo lsof -i :80
echo ""
echo "Checking for processes using port 443:"
sudo lsof -i :443
echo ""

### Step 5: Run Apache configuration test.
echo "Step 5: Running apache2ctl configtest:"
apache2ctl configtest
echo ""

echo "----------------------------------------"
echo "Troubleshooting complete."
