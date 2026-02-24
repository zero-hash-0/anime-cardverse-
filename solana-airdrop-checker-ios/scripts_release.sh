#!/bin/zsh
set -euo pipefail
PROJECT='AirdropChecker.xcodeproj'
SCHEME='AirdropChecker'
ARCHIVE_PATH='build/AirdropChecker.xcarchive'
EXPORT_PATH='build/export'

xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination 'generic/platform=iOS' -archivePath "$ARCHIVE_PATH" -allowProvisioningUpdates archive

xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" -exportOptionsPlist ExportOptions-AppStore.plist -allowProvisioningUpdates

echo "Archive + export completed: $EXPORT_PATH"
