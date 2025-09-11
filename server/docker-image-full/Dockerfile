FROM nginx:alpine

# Install necessary tools
RUN apk add --no-cache sed

# Copy all plugin data into the image
COPY ../../jenkins-mirror /usr/share/nginx/html

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Add script to update URLs in update-center.json
COPY update-urls.sh /usr/local/bin/update-urls.sh
RUN chmod +x /usr/local/bin/update-urls.sh

# Update URLs during build time
ARG SERVER_URL=http://localhost:8080
RUN /usr/local/bin/update-urls.sh "$SERVER_URL"

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]