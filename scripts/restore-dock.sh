#!/usr/bin/env bash
set -euo pipefail

echo "==> Restoring macOS system Dock settings..."

# Remove 1000s autohide delay
defaults delete com.apple.dock autohide-delay 2>/dev/null || true

# Turn off autohide if desired, or reset to standard macOS behavior
defaults write com.apple.dock autohide -bool false 2>/dev/null || true

# Restart Dock process
killall Dock 2>/dev/null || true

echo "==> macOS Dock has been restored and restarted."
