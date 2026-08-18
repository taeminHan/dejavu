#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
project_version="$(sed -n 's:.*<Version>\([^<]*\)</Version>.*:\1:p' "${repo_root}/ClaudeUsageTray.csproj" | head -1)"
[[ -n "${project_version}" ]] || { print -u2 "Could not read the Windows project version"; exit 1; }
version="${VERSION:-${project_version}}"
[[ "${version}" == "${project_version}" ]] || {
  print -u2 "macOS version ${version} does not match Windows project version ${project_version}"
  exit 1
}
build_number="${BUILD_NUMBER:?Set BUILD_NUMBER to an increasing integer}"
team_id="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
public_key="${SPARKLE_PUBLIC_KEY:?Set SPARKLE_PUBLIC_KEY}"
private_key="${SPARKLE_ED_PRIVATE_KEY:?Set SPARKLE_ED_PRIVATE_KEY}"
notary_key="${APPLE_NOTARY_KEY_PATH:?Set APPLE_NOTARY_KEY_PATH}"
notary_key_id="${APPLE_NOTARY_KEY_ID:?Set APPLE_NOTARY_KEY_ID}"
notary_issuer="${APPLE_NOTARY_ISSUER_ID:?Set APPLE_NOTARY_ISSUER_ID}"
output_root="${OUTPUT_ROOT:-${repo_root}/outputs/dejavu-macos-release}"
derived_data="${DERIVED_DATA_PATH:-${output_root}/DerivedData}"
archive_path="${output_root}/Dejavu.xcarchive"
export_path="${output_root}/export"
appcast_source="${output_root}/appcast-source"
export_options="${output_root}/ExportOptions.plist"
download_url_prefix="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/taeminHan/dejavu/releases/download/v${version}/}"

mkdir -p "${output_root}" "${appcast_source}"

cat > "${export_options}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>${team_id}</string>
</dict></plist>
PLIST

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

xcodebuild \
  -project "${repo_root}/macos/DejavuMac.xcodeproj" \
  -scheme DejavuMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${derived_data}" \
  -archivePath "${archive_path}" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="${team_id}" \
  MARKETING_VERSION="${version}" \
  CURRENT_PROJECT_VERSION="${build_number}" \
  DEJAVU_SPARKLE_PUBLIC_KEY="${public_key}" \
  archive

xcodebuild -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${export_path}" \
  -exportOptionsPlist "${export_options}" \
  -allowProvisioningUpdates

app_path="${export_path}/Dejavu.app"
notary_upload="${output_root}/Dejavu-notary.zip"
ditto -c -k --keepParent "${app_path}" "${notary_upload}"
xcrun notarytool submit "${notary_upload}" --wait \
  --key "${notary_key}" --key-id "${notary_key_id}" --issuer "${notary_issuer}"
xcrun stapler staple "${app_path}"
xcrun stapler validate "${app_path}"
codesign --verify --deep --strict --verbose=2 "${app_path}"
spctl --assess --type execute --verbose=2 "${app_path}"

update_zip="${appcast_source}/Dejavu-macOS-arm64.zip"
ditto -c -k --keepParent "${app_path}" "${update_zip}"

dmg_path="${output_root}/Dejavu-macOS-arm64.dmg"
hdiutil create -volname Dejavu -srcfolder "${app_path}" -ov -format UDZO "${dmg_path}"
xcrun notarytool submit "${dmg_path}" --wait \
  --key "${notary_key}" --key-id "${notary_key_id}" --issuer "${notary_issuer}"
xcrun stapler staple "${dmg_path}"
xcrun stapler validate "${dmg_path}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${dmg_path}"

generate_appcast="${derived_data}/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
[[ -x "${generate_appcast}" ]] || { print -u2 "Sparkle generate_appcast was not resolved"; exit 1; }
printf '%s' "${private_key}" | "${generate_appcast}" \
  --ed-key-file - \
  --download-url-prefix "${download_url_prefix}" \
  -o "${appcast_source}/appcast-macos.xml" \
  "${appcast_source}"

cp "${appcast_source}/Dejavu-macOS-arm64.zip" "${output_root}/"
cp "${appcast_source}/appcast-macos.xml" "${output_root}/"
(
  cd "${output_root}"
  shasum -a 256 Dejavu-macOS-arm64.dmg Dejavu-macOS-arm64.zip appcast-macos.xml \
    > SHA256SUMS-macOS.txt
)

print "Verified macOS release artifacts: ${output_root}"
