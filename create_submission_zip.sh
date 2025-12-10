#!/bin/bash

# Create submission zip excluding unnecessary files
ZIP_NAME="8BallMarkets_Submission_$(date +%Y%m%d).zip"

# Create zip excluding common build/dependency directories
zip -r "$ZIP_NAME" . \
  -x "*.git/*" \
  -x "*node_modules/*" \
  -x "*.next/*" \
  -x "*dist/*" \
  -x "*build/*" \
  -x "*.DS_Store" \
  -x "*.log" \
  -x "*.env.local" \
  -x "*.env.production" \
  -x "*/.env" \
  -x "*supabase/.branches/*" \
  -x "*supabase/.temp/*" \
  -x "*.zip" \
  -x "*.tar.gz" \
  -x "*__pycache__/*" \
  -x "*.pyc" \
  -x "*coverage/*" \
  -x "*.swp" \
  -x "*.swo" \
  -x "*~"

echo "Created: $ZIP_NAME"
ls -lh "$ZIP_NAME"
