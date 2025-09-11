#!/bin/sh

# Update URLs in update-center.json to point to the specified server
UPDATE_CENTER_FILE="/usr/share/nginx/html/update-center.json"
SERVER_URL="${1:-http://localhost:8080}"

if [ -f "$UPDATE_CENTER_FILE" ]; then
    echo "Updating URLs in update-center.json to point to $SERVER_URL"
    
    # Create a backup
    cp "$UPDATE_CENTER_FILE" "$UPDATE_CENTER_FILE.backup"
    
    # Replace the placeholder URL with the actual server URL
    sed -i "s|http://your-mirror.example.com|$SERVER_URL|g" "$UPDATE_CENTER_FILE"
    
    echo "URLs updated successfully"
else
    echo "Warning: update-center.json not found at $UPDATE_CENTER_FILE"
fi