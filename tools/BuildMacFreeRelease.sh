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
public_key="${SPARKLE_PUBLIC_KEY:-bCWiRQh8qw0hCNQBihOz/OSg1GJYymWoGTxvm7k2WLg=}"
key_account="${SPARKLE_KEY_ACCOUNT:-dev.taemtaem.dejavu}"
output_root="${OUTPUT_ROOT:-${repo_root}/outputs/dejavu-macos-free-release}"
derived_data="${DERIVED_DATA_PATH:-${output_root}/DerivedData}"
download_url_prefix="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/taeminHan/dejavu/releases/download/v${version}/}"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "${output_root}"
work_root="$(mktemp -d "${output_root}/release-work.XXXXXX")"
appcast_source="${work_root}/appcast-source"
staging_root="${work_root}/dmg-root"
mkdir -p "${appcast_source}" "${staging_root}"
cleanup() {
  rm -rf "${work_root}"
}
trap cleanup EXIT
if [[ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  sparkle_tools_hint="Use SPARKLE_ED_PRIVATE_KEY in CI or keep the ${key_account} key in the local Keychain."
else
  sparkle_tools_hint=""
fi

xcodebuild \
  -project "${repo_root}/macos/DejavuMac.xcodeproj" \
  -scheme DejavuMac \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "${derived_data}" \
  MARKETING_VERSION="${version}" \
  CURRENT_PROJECT_VERSION="${build_number}" \
  DEJAVU_SPARKLE_PUBLIC_KEY="${public_key}" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  SWIFT_SUPPRESS_WARNINGS=NO \
  build

source_app="${derived_data}/Build/Products/Release/Dejavu.app"
app_path="${staging_root}/Dejavu.app"
ditto "${source_app}" "${app_path}"

# A consistent ad-hoc signature is sufficient for local integrity and lets
# Sparkle replace the bundle. It does not establish an Apple-verified identity.
codesign --force --deep --sign - --timestamp=none "${app_path}"
codesign --verify --deep --strict --verbose=2 "${app_path}"

ln -s /Applications "${staging_root}/Applications" 2>/dev/null || true

update_zip="${appcast_source}/Dejavu-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${update_zip}"

dmg_path="${output_root}/Dejavu-macOS-arm64.dmg"
hdiutil create -volname Dejavu -srcfolder "${staging_root}" -ov -format UDZO "${dmg_path}"

generate_appcast="${derived_data}/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
[[ -x "${generate_appcast}" ]] || { print -u2 "Sparkle generate_appcast was not resolved"; exit 1; }

if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  printf '%s' "${SPARKLE_ED_PRIVATE_KEY}" | "${generate_appcast}" \
    --ed-key-file - \
    --download-url-prefix "${download_url_prefix}" \
    -o "${appcast_source}/appcast-macos.xml" \
    "${appcast_source}"
else
  "${generate_appcast}" \
    --account "${key_account}" \
    --download-url-prefix "${download_url_prefix}" \
    -o "${appcast_source}/appcast-macos.xml" \
    "${appcast_source}"
fi

signature="$(xmllint --xpath \
  'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' \
  "${appcast_source}/appcast-macos.xml")"
[[ -n "${signature}" ]] || { print -u2 "Sparkle archive signature is missing"; exit 1; }
sign_update="${derived_data}/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -x "${sign_update}" ]] || { print -u2 "Sparkle sign_update was not resolved"; exit 1; }
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  printf '%s' "${SPARKLE_ED_PRIVATE_KEY}" | "${sign_update}" \
    --ed-key-file - \
    --verify \
    "${update_zip}" \
    "${signature}"
else
  "${sign_update}" \
    --account "${key_account}" \
    --verify \
    "${update_zip}" \
    "${signature}"
fi

cp "${update_zip}" "${output_root}/Dejavu-macOS-arm64.zip"
cp "${appcast_source}/appcast-macos.xml" "${output_root}/appcast-macos.xml"
(
  cd "${output_root}"
  shasum -a 256 Dejavu-macOS-arm64.dmg Dejavu-macOS-arm64.zip appcast-macos.xml \
    > SHA256SUMS-macOS.txt
  shasum -a 256 -c SHA256SUMS-macOS.txt
)

verification_root="${work_root}/verification"
mkdir -p "${verification_root}"
ditto -x -k "${output_root}/Dejavu-macOS-arm64.zip" "${verification_root}"
verified_app="${verification_root}/Dejavu.app"
codesign --verify --deep --strict --verbose=2 "${verified_app}"
[[ "$(plutil -extract CFBundleShortVersionString raw "${verified_app}/Contents/Info.plist")" == "${version}" ]]
[[ "$(plutil -extract CFBundleVersion raw "${verified_app}/Contents/Info.plist")" == "${build_number}" ]]
[[ "$(plutil -extract SUPublicEDKey raw "${verified_app}/Contents/Info.plist")" == "${public_key}" ]]
file "${verified_app}/Contents/MacOS/Dejavu" | grep -q 'arm64'
test -x "${verified_app}/Contents/Helpers/dejavu-claude-bridge"
test -d "${verified_app}/Contents/PlugIns/DejavuUsageWidget.appex"
[[ "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw \
  "${verified_app}/Contents/PlugIns/DejavuUsageWidget.appex/Contents/Info.plist")" \
  == "com.apple.widgetkit-extension" ]]
xmllint --noout "${output_root}/appcast-macos.xml"
grep -q "<sparkle:version>${build_number}</sparkle:version>" \
  "${output_root}/appcast-macos.xml"
grep -q "<sparkle:shortVersionString>${version}</sparkle:shortVersionString>" \
  "${output_root}/appcast-macos.xml"
grep -q "${download_url_prefix}Dejavu-macOS-arm64.zip" \
  "${output_root}/appcast-macos.xml"

print "Free-distribution artifacts: ${output_root}"
print "This build is ad-hoc signed and not notarized. Users must approve its first launch in Privacy & Security."
[[ -z "${sparkle_tools_hint}" ]] || print "${sparkle_tools_hint}"
