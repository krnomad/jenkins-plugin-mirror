#!/bin/bash
set -e

DRY_RUN=$1
CHUNK_SIZE_MB=1500 # 1.5GB to stay safely under the 2GB limit  
MAX_FILE_SIZE_MB=1024 # Skip files larger than 1GB individually
PLUGINS_JSON_URL="https://updates.jenkins.io/current/update-center.actual.json"

echo "Fetching plugin list from Jenkins update center..."
curl -sL $PLUGINS_JSON_URL | sed 's/^updateCenter\.post(\(.*\);$/\1/' > plugins.json

echo "Generating plugin download list with URLs, sizes, and checksums..."
# Extract URL, size in bytes, and SHA256
jq -r '.plugins[] | select(.size != null and .size < ('$MAX_FILE_SIZE_MB' * 1024 * 1024)) | "\(.url) \(.size) \(.sha256)"' plugins.json > plugin_list_with_sizes.txt

# Count total plugins and size
TOTAL_PLUGINS=$(wc -l < plugin_list_with_sizes.txt)
TOTAL_SIZE_BYTES=$(awk '{sum += $2} END {print sum}' plugin_list_with_sizes.txt)
TOTAL_SIZE_MB=$((TOTAL_SIZE_BYTES / 1024 / 1024))

echo "Total plugins: $TOTAL_PLUGINS ($(du -h plugin_list_with_sizes.txt | cut -f1) list file)"
echo "Total size: ${TOTAL_SIZE_MB}MB"
echo "Skipped plugins larger than ${MAX_FILE_SIZE_MB}MB for safety"

if [ "$DRY_RUN" = "true" ]; then
  echo "Dry-run mode enabled. Using only first 3 plugins."
  head -n 3 plugin_list_with_sizes.txt > plugin_list.txt
else
  cp plugin_list_with_sizes.txt plugin_list.txt
fi

echo "Splitting plugin list into size-based chunks of max ${CHUNK_SIZE_MB}MB..."

# Improved chunking by actual file size
# Simple bash-based chunking for now (can be improved with Python later)
current_chunk=1
current_size=0
> "chunk_${current_chunk}.txt"

while read -r url size_bytes sha256; do
    size_mb=$((size_bytes / 1024 / 1024))
    
    # If adding this file would exceed chunk size, start new chunk  
    if [ $((current_size + size_mb)) -gt $CHUNK_SIZE_MB ] && [ -s "chunk_${current_chunk}.txt" ]; then
        echo "Chunk $current_chunk: ${current_size}MB"
        current_chunk=$((current_chunk + 1))
        current_size=0
        > "chunk_${current_chunk}.txt"
    fi
    
    # Add to current chunk
    echo "$url $sha256" >> "chunk_${current_chunk}.txt"
    current_size=$((current_size + size_mb))
done < plugin_list.txt

echo "Chunk $current_chunk: ${current_size}MB"

echo "Created $(ls chunk_*.txt 2>/dev/null | wc -l) chunk manifest(s)."