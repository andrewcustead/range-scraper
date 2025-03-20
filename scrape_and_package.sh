#!/bin/bash
# This script scrapes a list of domains, resolves their IP addresses,
# and packages the scraped websites along with a generated websites.txt file.
# Usage: ./scrape_and_package.sh domains_list.txt

# Check if a file containing the domains was provided
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 domains_list.txt"
  exit 1
fi

DOMAINS_FILE="$1"
SCRAPE_ROOT="/tmp/scraped_sites"
OUTPUT_ARCHIVE="trafficsites.tar.gz"
WEBSITES_FILE="websites.txt"

# Create a clean directory for scraping results
rm -rf "$SCRAPE_ROOT"
mkdir -p "$SCRAPE_ROOT"

# Clear any previous websites.txt
> "$SCRAPE_ROOT/$WEBSITES_FILE"

# Loop through each domain in the provided list
while IFS= read -r domain; do
  # Remove extra whitespace and skip empty lines
  domain=$(echo "$domain" | xargs)
  [ -z "$domain" ] && continue

  echo "Scraping $domain ..."

  # Create a directory for this domain
  DOMAIN_DIR="$SCRAPE_ROOT/$domain"
  mkdir -p "$DOMAIN_DIR"

  # Scrape the website using wget (mirror the site, convert links, fetch page requisites)
  wget --mirror --convert-links --adjust-extension --page-requisites --no-parent "http://$domain" -P "$DOMAIN_DIR"

  # Resolve the domain to an IP address (using dig, with fallback to host)
  ip=$(dig +short "$domain" | head -n 1)
  if [ -z "$ip" ]; then
    ip=$(host "$domain" | awk '/has address/ { print $4; exit }')
  fi

  # Append the domain and its IP to websites.txt if an IP was found
  if [ -n "$ip" ]; then
    echo "$domain,$ip" >> "$SCRAPE_ROOT/$WEBSITES_FILE"
    echo "Added $domain with IP $ip to websites.txt"
  else
    echo "Could not resolve IP for $domain. Skipping IP entry."
  fi
done < "$DOMAINS_FILE"

# Package the entire scraped_sites directory into a tar.gz archive
tar -czvf "$OUTPUT_ARCHIVE" -C "$SCRAPE_ROOT" .
echo "Packaging complete. Archive created: $OUTPUT_ARCHIVE"
