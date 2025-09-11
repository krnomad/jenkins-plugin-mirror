#!/bin/bash
set -e

MIRROR_TYPE=$1
DRY_RUN=$2
CHUNK_SIZE_MB=800  # Safe chunk size for GitHub Actions
PLUGINS_JSON_URL="https://updates.jenkins.io/current/update-center.actual.json"

# Configuration based on mirror type
case "$MIRROR_TYPE" in
    "dry-run")
        MAX_FILE_SIZE_MB=200
        MAX_VERSIONS_PER_PLUGIN=3
        USE_RSYNC=false
        echo "=== DRY RUN MODE ==="
        ;;
    "essential-only")
        MAX_FILE_SIZE_MB=200
        MAX_VERSIONS_PER_PLUGIN=3
        USE_RSYNC=false
        echo "=== ESSENTIAL ONLY MODE ==="
        ;;
    "comprehensive")
        MAX_FILE_SIZE_MB=1000  # 1GB limit for comprehensive
        MAX_VERSIONS_PER_PLUGIN=10  # More versions for legacy support
        USE_RSYNC=true
        echo "=== COMPREHENSIVE MODE ==="
        ;;
    "full-filtered")
        MAX_FILE_SIZE_MB=500
        MAX_VERSIONS_PER_PLUGIN=5
        USE_RSYNC=false
        echo "=== FULL FILTERED MODE ==="
        ;;
    *)
        echo "Error: Unknown mirror type '$MIRROR_TYPE'"
        echo "Usage: $0 {dry-run|essential-only|comprehensive|full-filtered} [true|false]"
        exit 1
        ;;
esac

echo "Settings:"
echo "- Mirror type: ${MIRROR_TYPE}"
echo "- Max file size: ${MAX_FILE_SIZE_MB}MB"
echo "- Max versions per plugin: ${MAX_VERSIONS_PER_PLUGIN}"
echo "- Chunk size: ${CHUNK_SIZE_MB}MB"
echo "- Use rsync: ${USE_RSYNC}"
echo "- Dry run: ${DRY_RUN}"

echo "Fetching plugin list from Jenkins update center..."
curl -sL $PLUGINS_JSON_URL | sed 's/^updateCenter\.post(\(.*\);$/\1/' > plugins.json

echo "Generating comprehensive plugin download list..."

# Create enhanced Python script for comprehensive filtering
cat > filter_plugins_comprehensive.py << 'EOF'
import json
import sys
import subprocess
from collections import defaultdict
from packaging import version
import re
import os

def parse_version(v):
    """Parse version string, handling Jenkins-specific formats"""
    # Remove common Jenkins prefixes and suffixes
    v = re.sub(r'^v?', '', v)
    v = re.sub(r'(-.*)?$', '', v.split('-')[0])
    try:
        return version.parse(v)
    except:
        return version.parse("0.0.0")

def get_plugin_popularity_score(plugin_info):
    """Calculate popularity score based on various metrics"""
    score = 0
    
    # Base score from popularity field
    if 'popularity' in plugin_info:
        score += plugin_info['popularity']
    
    # Bonus for recent releases
    if 'releaseTimestamp' in plugin_info:
        try:
            from datetime import datetime
            release_date = datetime.fromisoformat(plugin_info['releaseTimestamp'].replace('Z', '+00:00'))
            days_since_release = (datetime.now(release_date.tzinfo) - release_date).days
            if days_since_release < 365:  # Released within a year
                score += 1000
            elif days_since_release < 730:  # Within 2 years
                score += 500
        except:
            pass
    
    # Bonus for having dependencies (indicates it's a library)
    if 'dependencies' in plugin_info and plugin_info['dependencies']:
        score += len(plugin_info['dependencies']) * 100
    
    return score

def fetch_historical_versions_rsync(plugin_name, max_versions, use_rsync):
    """Fetch historical versions using rsync if enabled"""
    if not use_rsync:
        return []
    
    try:
        # List available versions from rsync
        cmd = f"timeout 30 rsync --list-only rsync://rsync.osuosl.org/jenkins/plugins/{plugin_name}/"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            versions = []
            for line in result.stdout.split('\n'):
                if '.hpi' in line or '.jpi' in line:
                    parts = line.split()
                    if len(parts) >= 5:
                        # Extract version from filename or directory
                        filename = parts[-1]
                        if filename.endswith('.hpi') or filename.endswith('.jpi'):
                            # Try to extract version from filename
                            version_match = re.search(r'(\d+(?:\.\d+)*(?:-[\w\.-]*)?)', filename)
                            if version_match:
                                versions.append({
                                    'version': version_match.group(1),
                                    'url': f"rsync://rsync.osuosl.org/jenkins/plugins/{plugin_name}/{filename}",
                                    'size': int(parts[1]) if parts[1].isdigit() else 0
                                })
            
            # Sort by version and return latest N
            versions.sort(key=lambda x: parse_version(x['version']), reverse=True)
            return versions[:max_versions]
            
    except Exception as e:
        print(f"Warning: Failed to fetch historical versions for {plugin_name}: {e}", file=sys.stderr)
    
    return []

# Parse arguments
mirror_type = sys.argv[1]
max_file_size = int(sys.argv[2]) * 1024 * 1024  # Convert MB to bytes
max_versions = int(sys.argv[3])
use_rsync = sys.argv[4].lower() == 'true'
dry_run = sys.argv[5].lower() == 'true'

print(f"Processing with mirror type: {mirror_type}")

with open('plugins.json', 'r') as f:
    data = json.load(f)

# Group plugins by name (without version)
plugin_groups = defaultdict(list)
all_plugins = []

for plugin_name, plugin_info in data['plugins'].items():
    if 'size' not in plugin_info or plugin_info['size'] is None:
        continue
    
    size_bytes = plugin_info['size']
    if size_bytes > max_file_size:
        continue
        
    # Add popularity score
    plugin_info['popularity_score'] = get_plugin_popularity_score(plugin_info)
    
    # Extract base plugin name
    base_name = plugin_name.split(':')[0] if ':' in plugin_name else plugin_name
    
    plugin_entry = {
        'name': plugin_name,
        'base_name': base_name,
        'info': plugin_info,
        'version': plugin_info.get('version', '0.0.0'),
        'source': 'update_center'
    }
    
    plugin_groups[base_name].append(plugin_entry)
    all_plugins.append(plugin_entry)

# For comprehensive mode, add historical versions
if use_rsync and mirror_type == 'comprehensive':
    print("Fetching historical versions via rsync...")
    processed_count = 0
    
    for base_name in list(plugin_groups.keys())[:50]:  # Limit for GitHub Actions time
        processed_count += 1
        if processed_count % 10 == 0:
            print(f"Processed {processed_count} plugins for historical versions...")
        
        historical_versions = fetch_historical_versions_rsync(base_name, max_versions, True)
        
        for hist_version in historical_versions:
            # Only add if not already present from update center
            existing_versions = [p['version'] for p in plugin_groups[base_name]]
            if hist_version['version'] not in existing_versions:
                plugin_entry = {
                    'name': f"{base_name}:{hist_version['version']}",
                    'base_name': base_name,
                    'info': {
                        'url': hist_version['url'],
                        'size': hist_version['size'],
                        'version': hist_version['version'],
                        'popularity_score': 100  # Lower score for historical
                    },
                    'version': hist_version['version'],
                    'source': 'rsync_historical'
                }
                plugin_groups[base_name].append(plugin_entry)
                all_plugins.append(plugin_entry)

# Filter and sort plugins
filtered_plugins = []
total_size = 0
skipped_versions = 0

print(f"Filtering plugins by priority and versions...")

for base_name, plugins in plugin_groups.items():
    # Sort by popularity score first, then by version
    try:
        sorted_plugins = sorted(plugins, 
                              key=lambda x: (x['info'].get('popularity_score', 0), parse_version(x['version'])), 
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

print(f"Original plugins in update center: {len(data['plugins'])}")
print(f"Total plugins after rsync enhancement: {len(all_plugins)}")
print(f"After filtering (max {max_versions} per plugin): {len(filtered_plugins)}")
print(f"Skipped {skipped_versions} older versions")
print(f"Total filtered size: {total_size // 1024 // 1024} MB")

# Output filtered plugin list
with open('plugin_list_comprehensive.txt', 'w') as f:
    for plugin in filtered_plugins:
        info = plugin['info']
        url = info['url']
        size = info['size']
        sha256 = info.get('sha256', '')
        source = plugin.get('source', 'update_center')
        f.write(f"{url} {size} {sha256} {source}\n")

if dry_run:
    print("Dry-run mode: limiting to first 5 plugins")
    with open('plugin_list_comprehensive.txt', 'r') as f:
        lines = f.readlines()[:5]
    with open('plugin_list_comprehensive.txt', 'w') as f:
        f.writelines(lines)

final_count = min(5, len(filtered_plugins)) if dry_run else len(filtered_plugins)
print(f"Created comprehensive plugin list: {final_count} plugins")
EOF

# Run the comprehensive filtering
echo "Running comprehensive filtering..."
python3 filter_plugins_comprehensive.py "$MIRROR_TYPE" $MAX_FILE_SIZE_MB $MAX_VERSIONS_PER_PLUGIN $USE_RSYNC $DRY_RUN

# Copy to standard filename for compatibility
cp plugin_list_comprehensive.txt plugin_list.txt

echo "Splitting into size-optimized chunks..."

# Enhanced chunking logic
current_chunk=1
current_size=0
> "chunk_${current_chunk}.txt"

while read -r url size_bytes sha256 source; do
    size_mb=$((size_bytes / 1024 / 1024))
    
    # If adding this file would exceed chunk size, start new chunk  
    if [ $((current_size + size_mb)) -gt $CHUNK_SIZE_MB ] && [ -s "chunk_${current_chunk}.txt" ]; then
        echo "Chunk $current_chunk: ${current_size}MB"
        current_chunk=$((current_chunk + 1))
        current_size=0
        > "chunk_${current_chunk}.txt"
    fi
    
    # Add to current chunk with source info
    echo "$url $sha256 $source" >> "chunk_${current_chunk}.txt"
    current_size=$((current_size + size_mb))
done < plugin_list.txt

echo "Chunk $current_chunk: ${current_size}MB"
echo "Created $(ls chunk_*.txt 2>/dev/null | wc -l) chunk manifest(s)."

# Create summary
echo "=== COMPREHENSIVE MIRROR SUMMARY ==="
TOTAL_PLUGINS=$(wc -l < plugin_list.txt)
TOTAL_SIZE_MB=$(awk '{sum += $2} END {print int(sum/1024/1024)}' plugin_list.txt)
UPDATE_CENTER_COUNT=$(grep -c "update_center" plugin_list.txt || echo "0")
RSYNC_COUNT=$(grep -c "rsync_historical" plugin_list.txt || echo "0")

echo "Mirror Type: $MIRROR_TYPE"
echo "Total Plugins: $TOTAL_PLUGINS"
echo "Total Size: ${TOTAL_SIZE_MB}MB"
echo "From Update Center: $UPDATE_CENTER_COUNT"
echo "From Historical Rsync: $RSYNC_COUNT"
echo "Chunks Created: $(ls chunk_*.txt 2>/dev/null | wc -l)"

# Cleanup
rm -f filter_plugins_comprehensive.py plugin_list_comprehensive.txt plugins.json