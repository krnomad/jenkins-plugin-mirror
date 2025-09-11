FROM nginx:alpine

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Create directory for jenkins plugins (will be mounted as volume)
RUN mkdir -p /usr/share/nginx/html

# Add script to update URLs in update-center.json dynamically
COPY update-urls.sh /usr/local/bin/update-urls.sh
RUN chmod +x /usr/local/bin/update-urls.sh

# Use custom entrypoint to update URLs before starting nginx
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]