#!/bin/bash
set -e

DRY_RUN=$1
CHUNK_SIZE_MB=800  # Reduced from 1500MB to 800MB for safer processing
MAX_FILE_SIZE_MB=200  # Exclude files larger than 200MB
MAX_VERSIONS_PER_PLUGIN=3  # Only keep latest 3 versions of each plugin
PLUGINS_JSON_URL="https://updates.jenkins.io/current/update-center.actual.json"

echo "=== SMART JENKINS PLUGIN MIRROR GENERATOR ==="
echo "Settings:"
echo "- Max file size: ${MAX_FILE_SIZE_MB}MB"
echo "- Max versions per plugin: ${MAX_VERSIONS_PER_PLUGIN}"
echo "- Chunk size: ${CHUNK_SIZE_MB}MB"
echo "- Dry run: ${DRY_RUN}"

echo "Fetching plugin list from Jenkins update center..."
curl -sL $PLUGINS_JSON_URL | sed 's/^updateCenter\.post(\(.*\);$/\1/' > plugins.json

echo "Generating filtered plugin download list..."

# Create Python script for smart filtering
cat > filter_plugins.py << 'EOF'
import json
import sys
from collections import defaultdict
from packaging import version
import re

def parse_version(v):
    """Parse version string, handling Jenkins-specific formats"""
    # Remove common Jenkins prefixes and suffixes
    v = re.sub(r'^v?', '', v)
    v = re.sub(r'(-.*)?$', '', v.split('-')[0])
    try:
        return version.parse(v)
    except:
        return version.parse("0.0.0")

max_file_size = int(sys.argv[1]) * 1024 * 1024  # Convert MB to bytes
max_versions = int(sys.argv[2])
dry_run = sys.argv[3] == 'true'

with open('plugins.json', 'r') as f:
    data = json.load(f)

# Group plugins by name (without version)
plugin_groups = defaultdict(list)

for plugin_name, plugin_info in data['plugins'].items():
    if 'size' not in plugin_info or plugin_info['size'] is None:
        continue
    
    size_bytes = plugin_info['size']
    if size_bytes > max_file_size:
        continue
        
    # Extract base plugin name (remove version info)
    base_name = plugin_name.split(':')[0] if ':' in plugin_name else plugin_name
    
    plugin_groups[base_name].append({
        'name': plugin_name,
        'info': plugin_info,
        'version': plugin_info.get('version', '0.0.0')
    })

# Keep only latest N versions of each plugin
filtered_plugins = []
total_size = 0
skipped_large = 0
skipped_versions = 0

for base_name, plugins in plugin_groups.items():
    # Sort by version (latest first)
    try:
        sorted_plugins = sorted(plugins, 
                              key=lambda x: parse_version(x['version']), 
                              reverse=True)
    except:
        sorted_plugins = sorted(plugins, 
                              key=lambda x: x['info'].get('releaseTimestamp', ''), 
                              reverse=True)
    
    # Keep only the latest N versions
    kept_plugins = sorted_plugins[:max_versions]
    skipped_versions += len(sorted_plugins) - len(kept_plugins)
    
    for plugin in kept_plugins:
        filtered_plugins.append(plugin)
        total_size += plugin['info']['size']

print(f"Original plugins: {len(data['plugins'])}")
print(f"After size filtering (>{max_file_size//1024//1024}MB): {len(data['plugins']) - skipped_large}")
print(f"After version filtering (max {max_versions} per plugin): {len(filtered_plugins)}")
print(f"Skipped {skipped_versions} older versions")
print(f"Total filtered size: {total_size // 1024 // 1024} MB")

# Output filtered plugin list
with open('plugin_list_filtered.txt', 'w') as f:
    for plugin in filtered_plugins:
        info = plugin['info']
        url = info['url']
        size = info['size']
        sha256 = info.get('sha256', '')
        f.write(f"{url} {size} {sha256}\n")

if dry_run:
    print("Dry-run mode: limiting to first 5 plugins")
    with open('plugin_list_filtered.txt', 'r') as f:
        lines = f.readlines()[:5]
    with open('plugin_list_filtered.txt', 'w') as f:
        f.writelines(lines)

final_count = min(5, len(filtered_plugins)) if dry_run else len(filtered_plugins)
print(f"Created filtered plugin list: {final_count} plugins")
EOF

# Run the filtering
python3 filter_plugins.py $MAX_FILE_SIZE_MB $MAX_VERSIONS_PER_PLUGIN $DRY_RUN

# Copy to standard filename for compatibility
cp plugin_list_filtered.txt plugin_list.txt

echo "Splitting into size-optimized chunks..."

# Improved chunking by actual file size
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

# Cleanup
rm -f filter_plugins.py plugin_list_filtered.txt plugins.json