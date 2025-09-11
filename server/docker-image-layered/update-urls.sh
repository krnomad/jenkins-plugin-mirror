#!/bin/sh

# Update URLs in update-center.json to point to the current server
UPDATE_CENTER_FILE="/usr/share/nginx/html/update-center.json"

if [ -f "$UPDATE_CENTER_FILE" ]; then
    # Get the server URL from environment variables
    SERVER_HOST=${NGINX_HOST:-localhost}
    SERVER_PORT=${NGINX_PORT:-80}
    
    if [ "$SERVER_PORT" = "80" ]; then
        SERVER_URL="http://$SERVER_HOST"
    else
        SERVER_URL="http://$SERVER_HOST:$SERVER_PORT"
    fi
    
    echo "Updating URLs in update-center.json to point to $SERVER_URL"
    
    # Create a backup
    cp "$UPDATE_CENTER_FILE" "$UPDATE_CENTER_FILE.backup"
    
    # Replace the placeholder URL with the actual server URL
    sed -i "s|http://your-mirror.example.com|$SERVER_URL|g" "$UPDATE_CENTER_FILE"
    
    echo "URLs updated successfully"
else
    echo "Warning: update-center.json not found at $UPDATE_CENTER_FILE"
fi