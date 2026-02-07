#!/bin/sh
set -e

REPO="jadnohra/recent-work"
BINARY="recent-work"
INSTALL_DIR="/usr/local/bin"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: macOS only" >&2
  exit 1
fi

echo "Fetching latest release..."
URL=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"browser_download_url".*tar\.gz"' \
  | head -1 \
  | cut -d '"' -f 4)

if [ -z "$URL" ]; then
  echo "error: could not find release" >&2
  exit 1
fi

echo "Downloading ${URL}..."
curl -fsSL "$URL" | tar xz -C "$TMP_DIR"

if [ -w "$INSTALL_DIR" ]; then
  cp "$TMP_DIR/$BINARY" "$INSTALL_DIR/$BINARY"
else
  echo "Need sudo to install to $INSTALL_DIR"
  sudo cp "$TMP_DIR/$BINARY" "$INSTALL_DIR/$BINARY"
fi

chmod +x "$INSTALL_DIR/$BINARY"

echo "Installed $BINARY to $INSTALL_DIR"
echo "Run: $BINARY init && $BINARY start"
