#!/bin/bash
# This script scrapes a list of domains, resolves their IP addresses,
# and packages the scraped websites along with a generated websites.txt file.
# It now displays a progress indicator for processing the list and includes a 5-second timeout for each wget command.
#
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

# Count the total number of non-empty lines (domains)
total_domains=$(grep -v '^\s*$' "$DOMAINS_FILE" | wc -l)
current=0

# Loop through each domain in the provided list
while IFS= read -r domain; do
  # Remove extra whitespace and skip empty lines
  domain=$(echo "$domain" | xargs)
  [ -z "$domain" ] && continue

  current=$((current + 1))
  percent=$(awk "BEGIN {printf \"%.0f\", ($current/$total_domains)*100}")
  # Display progress bar (overwrite the same line)
  printf "\rProgress: %d/%d (%s%%) - Scraping %s" "$current" "$total_domains" "$percent" "$domain"

  # Create a directory for this domain
  DOMAIN_DIR="$SCRAPE_ROOT/$domain"
  mkdir -p "$DOMAIN_DIR"

  # Use timeout to limit wget to 5 seconds and limit recursion to 2 levels
  if ! timeout 5s wget --mirror --convert-links --adjust-extension --page-requisites --no-parent -l 2 "http://$domain" -P "$DOMAIN_DIR"; then
    echo -e "\nTimeout reached for $domain, skipping..."
    continue
  fi

  # Resolve the domain to an IP address (using dig, with fallback to host)
  ip=$(dig +short "$domain" | head -n 1)
  if [ -z "$ip" ]; then
    ip=$(host "$domain" | awk '/has address/ { print $4; exit }')
  fi

  # Append the domain and its IP to websites.txt if an IP was found
  if [ -n "$ip" ]; then
    echo "$domain,$ip" >> "$SCRAPE_ROOT/$WEBSITES_FILE"
  fi

done < "$DOMAINS_FILE"

# Finish the progress line with a newline
echo -e "\nScraping complete."

# Package the entire scraped_sites directory into a tar.gz archive
tar -czvf "$OUTPUT_ARCHIVE" -C "$SCRAPE_ROOT" .
echo "Packaging complete. Archive created: $OUTPUT_ARCHIVE"
