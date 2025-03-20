#!/bin/bash
# This script scrapes a list of domains, resolves their IP addresses,
# and packages the scraped websites along with a generated websites.txt file.
# For each domain, the files are saved under /tmp/scraped_sites/sitename.com/files.
# It displays a progress indicator and enforces a 5-second timeout for wget.
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

  # Create the directory for the domain with a subfolder "files".
  DOMAIN_DIR="$SCRAPE_ROOT/$domain/files"
  mkdir -p "$DOMAIN_DIR"

  # Scrape the site using wget:
  #   --mirror           : Enable mirroring.
  #   --convert-links    : Convert links for local viewing.
  #   --adjust-extension : Save files with proper extensions.
  #   --page-requisites  : Download images, CSS, fonts, etc.
  #   --no-parent        : Do not ascend to parent directories.
  #   -l 2               : Limit recursion to 2 levels.
  #   -nH                : Do not create a host directory.
  #   -P <dir>          : Set the target directory.
  #
  # The -q option silences wget's output so the progress line remains visible.
  if ! timeout 5s wget --mirror --convert-links --adjust-extension --page-requisites --no-parent -l 1 -nH -q -P "$DOMAIN_DIR" "http://$domain"; then
    echo -e "\nTimeout reached for $domain, skipping..."
    continue
  fi

  # Resolve the domain to an IP address using dig; fallback to host.
  ip=$(dig +short "$domain" | head -n 1)
  if [ -z "$ip" ]; then
    ip=$(host "$domain" | awk '/has address/ { print $4; exit }')
  fi

  # Append the domain and its IP to websites.txt if found.
  if [ -n "$ip" ]; then
    echo "$domain,$ip" >> "$SCRAPE_ROOT/$WEBSITES_FILE"
  fi

done < "$DOMAINS_FILE"

# End the progress output.
echo -e "\nScraping complete."

# Package the entire scraped_sites directory into a tar.gz archive.
tar -czvf "$OUTPUT_ARCHIVE" -C "$SCRAPE_ROOT" .
echo "Packaging complete. Archive created: $OUTPUT_ARCHIVE"
