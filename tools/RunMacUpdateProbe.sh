#!/bin/bash
set -euo pipefail

# Native KVO/presentation regression only. Not a Sparkle integration/install test.
repository_dir="$(cd "$(dirname "$0")/.." && pwd)"
package_build_dir="${1:-/tmp/dejavu-macos-implementation-package}"
probe_output_dir="${2:-$(mktemp -d /tmp/dejavu-native-update-probe.XXXXXX)}"
if [[ -d "$package_build_dir/out/Products/Debug" ]]; then
    products_dir="$package_build_dir/out/Products/Debug"
elif [[ -d "$package_build_dir/arm64-apple-macosx/debug/Modules" ]]; then
    products_dir="$package_build_dir/arm64-apple-macosx/debug"
else
    echo "Build the macOS core package in the supplied scratch directory first." >&2
    exit 1
fi
module_search_dir="$products_dir"
if [[ -d "$products_dir/Modules" ]]; then module_search_dir="$products_dir/Modules"; fi
domain_objects=()
if [[ -f "$products_dir/DejavuDomain.o" ]]; then
    domain_objects+=("$products_dir/DejavuDomain.o")
elif [[ -d "$products_dir/DejavuDomain.build" ]]; then
    while IFS= read -r -d '' object; do domain_objects+=("$object"); done < <(find "$products_dir/DejavuDomain.build" -name '*.swift.o' -print0)
else
    echo "Missing production DejavuDomain objects." >&2
    exit 1
fi
application_dir="$probe_output_dir/MacUpdateProbe.app/Contents"
mkdir -p "$application_dir/MacOS" "$application_dir/Frameworks" "$probe_output_dir/modules"
cp "$repository_dir/tools/MacUpdateProbeSupport/Info.plist" "$application_dir/Info.plist"
xcrun swiftc -swift-version 6 -warnings-as-errors -emit-library -emit-module -module-name Sparkle \
    -module-cache-path "$probe_output_dir/module-cache" \
    -emit-module-path "$probe_output_dir/modules/Sparkle.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libSparkle.dylib \
    "$repository_dir/tools/MacUpdateProbeSupport/Sparkle.swift" \
    -o "$application_dir/Frameworks/libSparkle.dylib"
xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
    -module-cache-path "$probe_output_dir/module-cache" -I "$module_search_dir" -I "$probe_output_dir/modules" \
    -L "$application_dir/Frameworks" -lSparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "$repository_dir/macos/DejavuMac/Platform/Updates/UpdateCoordinator.swift" \
    "$repository_dir/tools/MacUpdateProbe.swift" "${domain_objects[@]}" \
    -o "$application_dir/MacOS/MacUpdateProbe"
"$application_dir/MacOS/MacUpdateProbe"
