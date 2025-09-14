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
MULTI_PART=$(echo "$RELEASE_INFO" | jq -r '.assets[].name' | grep -c "jenkins-plugins-comprehensive-part" || echo "0")

if [ "$MULTI_PART" -gt 0 ]; then
    echo "📦 Multi-part release detected (${MULTI_PART} parts)"
    echo "Downloading all parts and assembly script..."
    
    # Get the latest release tag
    RELEASE_TAG=$(gh release list --repo "$REPO_NAME" --limit 1 | grep comprehensive | cut -f3)
    echo "Downloading release: $RELEASE_TAG"
    
    # Use curl for stable download of large files (gh CLI has issues with 1GB+ files)
    echo "Using curl for reliable large file downloads..."
    for i in $(seq 1 25); do
        echo "Attempting to download part $i..."
        curl -L -f -o "jenkins-plugins-comprehensive-part$i.tar.gz" \
            "https://github.com/$REPO_NAME/releases/download/$RELEASE_TAG/jenkins-plugins-comprehensive-part$i.tar.gz" 2>/dev/null || {
            echo "Part $i not found (normal if fewer parts exist)"
            break
        }
        curl -L -f -o "jenkins-plugins-comprehensive-part$i.tar.gz.sha256" \
            "https://github.com/$REPO_NAME/releases/download/$RELEASE_TAG/jenkins-plugins-comprehensive-part$i.tar.gz.sha256" 2>/dev/null || {
            echo "Checksum for part $i not found"
        }
    done
    
    # Download assembly script
    curl -L -o "assemble-comprehensive-mirror.sh" \
        "https://github.com/$REPO_NAME/releases/download/$RELEASE_TAG/assemble-comprehensive-mirror.sh"
    
    echo "🔍 Verifying checksums..."
    for checksum_file in jenkins-plugins-comprehensive-part*.tar.gz.sha256; do
        if [ -f "$checksum_file" ]; then
            echo "Verifying $checksum_file..."
            sha256sum -c "$checksum_file"
        fi
    done
    
    echo "🔧 Assembling multi-part release..."
    chmod +x assemble-comprehensive-mirror.sh
    ./assemble-comprehensive-mirror.sh
    
    echo "🧹 Cleaning up part files..."
    rm -f jenkins-plugins-comprehensive-part*.tar.gz* assemble-comprehensive-mirror.sh
    
else
    echo "📦 Single-part release detected"
    mkdir -p "$DOWNLOAD_DIR"
    
    # Download single archive (fallback for older releases)
    gh release download --repo "$REPO_NAME" --pattern "jenkins-plugins-mirror.tar.gz*"
    
    echo "🔍 Verifying checksum..."
    sha256sum -c jenkins-plugins-mirror.tar.gz.sha256
    
    echo "📂 Extracting files..."
    tar -xzf jenkins-plugins-mirror.tar.gz -C "$DOWNLOAD_DIR"
    
    echo "🧹 Cleaning up..."
    rm jenkins-plugins-mirror.tar.gz jenkins-plugins-mirror.tar.gz.sha256
fi

# Determine the correct directory name based on what was created
if [ -d "jenkins-comprehensive-mirror" ]; then
    MIRROR_DIR="jenkins-comprehensive-mirror"
elif [ -d "$DOWNLOAD_DIR" ]; then
    MIRROR_DIR="$DOWNLOAD_DIR"
else
    MIRROR_DIR="jenkins-mirror"
fi

PLUGIN_COUNT=$(find "$MIRROR_DIR" -name "*.hpi" -o -name "*.jpi" 2>/dev/null | wc -l || echo "0")
TOTAL_SIZE_MB=$(du -sm "$MIRROR_DIR" 2>/dev/null | cut -f1 || echo "0")

echo ""
echo "✅ Success! Jenkins mirror is ready!"
echo "📊 Statistics:"
echo "   - Directory: $MIRROR_DIR/"
echo "   - Plugins: $PLUGIN_COUNT"
echo "   - Total Size: ${TOTAL_SIZE_MB}MB"
echo ""
echo "🔧 Next Steps:"
echo "   1. Deploy the mirror using one of these methods:"
echo "      - Docker Compose (recommended): cd server/docker-image-layered && docker-compose up"
echo "      - Host Nginx: Copy $MIRROR_DIR to /var/www/ and configure nginx"
echo "   2. Configure Jenkins Update Site URL:"
echo "      http://your-server/$MIRROR_DIR/update-center2/update-center.json"