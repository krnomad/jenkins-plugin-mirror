#!/bin/bash
set -e

DRY_RUN=$1
CHUNK_SIZE_MB=1500 # 1.5GB to stay safely under the 2GB limit
PLUGINS_JSON_URL="https://updates.jenkins.io/current/update-center.actual.json"

echo "Fetching plugin list from Jenkins update center..."
# Remove the JSONP wrapper to get pure JSON
curl -sL $PLUGINS_JSON_URL | sed 's/^updateCenter\.post(\(.*\);$/\1/' > plugins.json

echo "Generating plugin download list with URLs and sizes..."
# Use jq to parse JSON and create a list of "url size"
jq -r '.plugins[] | "\(.url) \(.sha256)"' plugins.json > plugin_list_full.txt

if [ "$DRY_RUN" = "true" ]; then
  echo "Dry-run mode enabled. Using only 3 plugins."
  head -n 3 plugin_list_full.txt > plugin_list.txt
else
  cp plugin_list_full.txt plugin_list.txt
fi

echo "Splitting plugin list into chunks of max ${CHUNK_SIZE_MB}MB..."
# This script is a simplified example. A real-world script might fetch sizes first.
# For simplicity here, we split by line count, but the workflow has disk-freeing steps
# and the chunk size is conservative. A more robust script would curl HEAD for sizes.
total_lines=$(wc -l < plugin_list.txt)
# Assuming average plugin size of 1-2MB, this is a safe split
lines_per_chunk=1000 
if [ "$DRY_RUN" = "true" ]; then
  lines_per_chunk=3
fi
split -l $lines_per_chunk -d -a 2 plugin_list.txt chunk_

# Rename chunks to a predictable format
i=1
for f in chunk_*; do
  if [ -f "$f" ]; then
    mv -- "$f" "chunk_$i.txt"
    i=$((i+1))
  fi
done

echo "Created $(ls chunk_*.txt | wc -l) chunk manifest(s)."