#!/bin/bash
# This script scrapes a list of domains, resolves their IP addresses,
# and packages the scraped websites along with a generated websites.txt file.
# For each domain, the scraped files are saved directly under /tmp/scraped_sites/sitename.com/
#
# Usage: ./scrape_and_package.sh domains_list.txt

# Verify that a domains file is provided.
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 domains_list.txt"
  exit 1
fi

DOMAINS_FILE="$1"
SCRAPE_ROOT="/tmp/scraped_sites"
OUTPUT_ARCHIVE="trafficsites.tar.gz"
WEBSITES_FILE="websites.txt"

# Clean the scrape root directory.
rm -rf "$SCRAPE_ROOT"
mkdir -p "$SCRAPE_ROOT"

# Clear any previous websites.txt.
> "$SCRAPE_ROOT/$WEBSITES_FILE"

# Count total non-empty lines (domains) in the input file.
total_domains=$(grep -v '^\s*$' "$DOMAINS_FILE" | wc -l)
current=0

# Loop through each domain.
while IFS= read -r domain; do
  # Trim whitespace and skip empty lines.
  domain=$(echo "$domain" | xargs)
  [ -z "$domain" ] && continue

  current=$((current + 1))
  percent=$(awk "BEGIN {printf \"%.0f\", ($current/$total_domains)*100}")
  # Update progress on the same line.
  printf "\rProgress: %d/%d (%s%%) - Scraping %s" "$current" "$total_domains" "$percent" "$domain"

  # Create the directory for the domain (directly under SCRAPE_ROOT)
  DOMAIN_DIR="$SCRAPE_ROOT/$domain"
  mkdir -p "$DOMAIN_DIR"

  # Use wget with options:
  #   -r              : recursive download.
  #   -l 1            : limit recursion to 1 level.
  #   -p              : download all page requisites (images, CSS, fonts, etc.).
  #   -k              : convert links for local viewing.
  #   -E              : adjust file extensions (e.g., save HTML files with .html extension).
  #   --no-parent     : do not ascend to parent directories.
  #   -nH             : do not create a directory named after the host.
  #   -e robots=off   : ignore robots.txt restrictions.
  #   --connect-timeout=5 --read-timeout=5 : set connection and read timeouts.
  #   --wait=2 --random-wait : adds a delay between requests.
  #   -U              : set a modern browser user-agent string.
  #
  # Wrapping wget in a timeout of 30 seconds overall (adjust if needed).
  if ! timeout --foreground 30s wget -r -l 1 -p -k -E --no-parent -nH -e robots=off --connect-timeout=5 --read-timeout=5 --wait=2 --random-wait -U "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.87 Safari/537.36" -P "$DOMAIN_DIR" "https://$domain" ; then
    echo -e "\nTimeout reached or cancelled for $domain, skipping..."
    continue
  fi

  # Resolve the domain to an IP address by querying A records.
  ip=$(dig +short A "$domain" | head -n 1)
  # If the result is not a valid IPv4 address, fallback to host.
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ip=$(host "$domain" | awk '/has address/ { if ($4 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $4; exit } }')
  fi

  # Append the domain and its IP to websites.txt only if a valid IPv4 address was obtained.
  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$domain,$ip" >> "$SCRAPE_ROOT/$WEBSITES_FILE"
  fi

done < "$DOMAINS_FILE"

# Finish the progress line.
echo -e "\nScraping complete."

# Package the entire scraped_sites directory into a tar.gz archive.
tar -czvf "$OUTPUT_ARCHIVE" -C "$SCRAPE_ROOT" .
echo "Packaging complete. Archive created: $OUTPUT_ARCHIVE"
