#!/bin/zsh
# Double-click to add editorIDs to the Development schema (see add-editor-ids-dev.mjs).
cd "$(dirname "$0")/.." || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/$(ls $HOME/.nvm/versions/node 2>/dev/null | tail -1)/bin:$PATH"
node scripts/add-editor-ids-dev.mjs
echo
echo "You can close this window."
