#!/bin/bash
set -e

PLUGINS_DIR=$1
OUTPUT_FILE=$2
BASE_URL="http://your-mirror.example.com/plugins" # This will be replaced by users

echo "Generating update-center.json from plugins in $PLUGINS_DIR..."

# Fetch the original JSON to use as a template for metadata
curl -sL "https://updates.jenkins.io/current/update-center.actual.json" | sed '1d;$d' > original.json

# Create the main JSON structure
echo "{" > temp.json
echo "  \"plugins\": {" >> temp.json

# Iterate over downloaded plugins
first=true
for hpi in $(find $PLUGINS_DIR -name "*.hpi"); do
  plugin_name=$(unzip -p $hpi META-INF/MANIFEST.MF | grep -E 'Plugin-Id|Short-Name' | head -n1 | cut -d: -f2 | tr -d ' \r')
  
  # Extract original plugin data from the template
  plugin_json=$(jq --arg name "$plugin_name" '.plugins[$name]' original.json)
  
  if [ "$plugin_json" != "null" ]; then
    if [ "$first" = "false" ]; then
      echo "," >> temp.json
    fi
    
    # Override URL to point to our mirror
    new_url="${BASE_URL}/$(basename $hpi)"
    updated_plugin_json=$(echo $plugin_json | jq --arg url "$new_url" '.url = $url')
    
    echo "    \"$plugin_name\": $updated_plugin_json" >> temp.json
    first=false
  fi
done

echo "  }," >> temp.json
# Copy other metadata from the original file
jq '.core, .warnings, .id, .signature' original.json >> temp.json
echo "}" >> temp.json

# Wrap in JSONP format
echo "updateCenter.post(" > $OUTPUT_FILE
cat temp.json >> $OUTPUT_FILE
echo ");" >> $OUTPUT_FILE

echo "Successfully created $OUTPUT_FILE"