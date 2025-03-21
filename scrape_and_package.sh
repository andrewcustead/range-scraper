#!/bin/bash
# This script scrapes a list of domains provided in a file.
# For each domain, it performs DNS resolution (using dig, host, nslookup, then getent),
# writes a line "domain,IP" to websites.txt, and then scrapes the website.
# Finally, it packages the scraped sites along with websites.txt into a tar.gz archive.
#
# Usage: ./scrape_and_package.sh domains_list.txt

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 domains_list.txt"
  exit 1
fi

DOMAINS_FILE="$1"
SCRAPE_ROOT="/tmp/scraped_sites"
OUTPUT_ARCHIVE="trafficsites.tar.gz"
WEBSITES_FILE="websites.txt"

# Clean the scrape directory
rm -rf "$SCRAPE_ROOT"
mkdir -p "$SCRAPE_ROOT"

# Create an empty websites.txt
> "$SCRAPE_ROOT/$WEBSITES_FILE"

total_domains=$(grep -v '^\s*$' "$DOMAINS_FILE" | wc -l)
current=0

while IFS= read -r domain; do
  # Trim whitespace and skip empty lines
  domain=$(echo "$domain" | xargs)
  [ -z "$domain" ] && continue

  current=$((current + 1))
  percent=$(awk "BEGIN {printf \"%.0f\", ($current/$total_domains)*100}")
  printf "\rProgress: %d/%d (%s%%) - Processing %s" "$current" "$total_domains" "$percent" "$domain"

  # Perform DNS resolution:
  ip=$(dig +short A "$domain" | head -n1)
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ip=$(host "$domain" 2>/dev/null | awk '/has address/ { print $4; exit }')
  fi
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ip=$(nslookup "$domain" 2>/dev/null | awk '/^Address: / { print $2; exit }')
  fi
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ip=$(getent ahosts "$domain" | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ { print $1; exit }')
  fi

  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$domain,$ip" >> "$SCRAPE_ROOT/$WEBSITES_FILE"
  else
    echo "Warning: Could not resolve $domain" >> "$SCRAPE_ROOT/websites_errors.log"
  fi

  # Create directory for this domain’s scrape.
  DOMAIN_DIR="$SCRAPE_ROOT/$domain"
  mkdir -p "$DOMAIN_DIR"

  # Scrape the website using wget:
  # -r: recursive, -l 2: limit recursion to 2 levels, -p: page requisites,
  # -k: convert links, -E: adjust extensions, --no-parent: do not ascend to parent dirs,
  # -nH: no host directory, --wait=2 and --random-wait to slow requests.
  timeout --foreground 30s wget -r -l 2 -p -k -E --no-parent -nH --wait=2 --random-wait \
    -U "Mozilla/5.0 (X11; Linux x86_64)" -P "$DOMAIN_DIR" "http://$domain"

done < "$DOMAINS_FILE"

echo -e "\nScraping complete."
tar -czvf "$OUTPUT_ARCHIVE" -C "$SCRAPE_ROOT" .
echo "Packaging complete. Archive created: $OUTPUT_ARCHIVE"
