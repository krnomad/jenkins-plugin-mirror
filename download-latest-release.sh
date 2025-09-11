#!/bin/bash
set -e

REPO_URL=$(git remote get-url origin 2>/dev/null || echo "https://github.com/krnomad/jenkins-plugin-mirror")
REPO_NAME=$(echo "$REPO_URL" | sed -e 's/.*github.com\///' -e 's/\.git$//')
DOWNLOAD_DIR="jenkins-mirror"

if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed. Please install it to proceed."
    exit 1
fi

echo "🔍 Fetching latest release from repository: $REPO_NAME"

# Check if release has multi-part files
RELEASE_INFO=$(gh release view --repo "$REPO_NAME" --json assets)
MULTI_PART=$(echo "$RELEASE_INFO" | jq -r '.assets[].name' | grep -c "jenkins-plugins-mirror-part" || echo "0")

if [ "$MULTI_PART" -gt 0 ]; then
    echo "📦 Multi-part release detected (${MULTI_PART} parts)"
    echo "Downloading all parts and assembly script..."
    
    # Download all multi-part files and assembly script
    gh release download --repo "$REPO_NAME" --latest --pattern "jenkins-plugins-mirror-part*.tar.gz*"
    gh release download --repo "$REPO_NAME" --latest --pattern "assemble-mirror.sh"
    
    echo "🔍 Verifying checksums..."
    for checksum_file in jenkins-plugins-mirror-part*.tar.gz.sha256; do
        if [ -f "$checksum_file" ]; then
            echo "Verifying $checksum_file..."
            sha256sum -c "$checksum_file"
        fi
    done
    
    echo "🔧 Assembling multi-part release..."
    chmod +x assemble-mirror.sh
    ./assemble-mirror.sh
    
    echo "🧹 Cleaning up part files..."
    rm -f jenkins-plugins-mirror-part*.tar.gz* assemble-mirror.sh
    
else
    echo "📦 Single-part release detected"
    mkdir -p "$DOWNLOAD_DIR"
    
    # Download single archive (fallback for older releases)
    gh release download --repo "$REPO_NAME" --latest --pattern "jenkins-plugins-mirror.tar.gz*"
    
    echo "🔍 Verifying checksum..."
    sha256sum -c jenkins-plugins-mirror.tar.gz.sha256
    
    echo "📂 Extracting files..."
    tar -xzf jenkins-plugins-mirror.tar.gz -C "$DOWNLOAD_DIR"
    
    echo "🧹 Cleaning up..."
    rm jenkins-plugins-mirror.tar.gz jenkins-plugins-mirror.tar.gz.sha256
fi

PLUGIN_COUNT=$(find "$DOWNLOAD_DIR/plugins" -name "*.hpi" 2>/dev/null | wc -l || echo "0")
TOTAL_SIZE_MB=$(du -sm "$DOWNLOAD_DIR" 2>/dev/null | cut -f1 || echo "0")

echo ""
echo "✅ Success! Jenkins mirror is ready!"
echo "📊 Statistics:"
echo "   - Directory: $DOWNLOAD_DIR/"
echo "   - Plugins: $PLUGIN_COUNT"
echo "   - Total Size: ${TOTAL_SIZE_MB}MB"
echo ""
echo "🔧 Next Steps:"
echo "   1. Edit '$DOWNLOAD_DIR/update-center.json' and replace 'http://your-mirror.example.com' with your server URL"
echo "   2. Choose a deployment method from README.md:"
echo "      - Docker Compose (recommended): cd server/docker-image-layered && docker-compose up"
echo "      - Host Nginx: Follow README.md instructions"