#!/bin/sh

# Update URLs in update-center.json before starting nginx
/usr/local/bin/update-urls.sh

# Start nginx
exec "$@"