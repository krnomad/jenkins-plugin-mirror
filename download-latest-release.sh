#!/bin/bash
set -e

REPO_URL=$(git remote get-url origin)
REPO_NAME=$(echo "$REPO_URL" | sed -e 's/.*github.com\///' -e 's/\.git$//')
DOWNLOAD_DIR="jenkins-mirror"

if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed. Please install it to proceed."
    exit 1
fi

echo "Fetching latest release from repository: $REPO_NAME"

mkdir -p "$DOWNLOAD_DIR"

gh release download --repo "$REPO_NAME" --latest -p "*.tar.gz*" -O .

echo "Verifying checksum..."
sha256sum -c jenkins-plugins-mirror.tar.gz.sha256

echo "Extracting files..."
tar -xzf jenkins-plugins-mirror.tar.gz -C "$DOWNLOAD_DIR"

echo "Cleaning up..."
rm jenkins-plugins-mirror.tar.gz jenkins-plugins-mirror.tar.gz.sha256

echo "✅ Success! Jenkins mirror files are ready in the '$DOWNLOAD_DIR' directory."
echo "Please edit '$DOWNLOAD_DIR/update-center.json' and replace 'http://your-mirror.example.com' with your actual server URL."
echo "Then, choose one of the deployment methods in README.md."