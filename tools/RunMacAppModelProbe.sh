#!/bin/bash
set -euo pipefail

# This probe compiles production AppModel/ProviderBrand plus production package
# objects. It does not start the application, real providers or authentication.
# First build/test the core package, then provide its scratch directory:
# bash tools/RunMacAppModelProbe.sh /tmp/dejavu-macos-implementation-package
repository_dir="$(cd "$(dirname "$0")/.." && pwd)"
package_build_dir="${1:-/tmp/dejavu-macos-implementation-package}"
probe_output_dir="${2:-$(mktemp -d /tmp/dejavu-native-app-model-probe.XXXXXX)}"

if [[ -d "$package_build_dir/out/Products/Debug" ]]; then
    products_dir="$package_build_dir/out/Products/Debug"
elif [[ -d "$package_build_dir/arm64-apple-macosx/debug/Modules" ]]; then
    products_dir="$package_build_dir/arm64-apple-macosx/debug"
else
    echo "Build the macOS core package in the supplied scratch directory first." >&2
    exit 1
fi

mkdir -p "$probe_output_dir"
module_search_dir="$products_dir"
if [[ -d "$products_dir/Modules" ]]; then module_search_dir="$products_dir/Modules"; fi
package_objects=()
for package in DejavuDomain DejavuApplication DejavuPersistence DejavuProviders DejavuWidgetShared; do
    if [[ -f "$products_dir/$package.o" ]]; then
        package_objects+=("$products_dir/$package.o")
    elif [[ -d "$products_dir/$package.build" ]]; then
        while IFS= read -r -d '' object; do package_objects+=("$object"); done < <(find "$products_dir/$package.build" -name '*.swift.o' -print0)
    else
        echo "Missing production package objects: $package" >&2
        exit 1
    fi
done

xcrun swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
    -module-cache-path "$probe_output_dir/module-cache" -I "$module_search_dir" \
    "$repository_dir/macos/DejavuMac/App/AppModel.swift" \
    "$repository_dir/macos/SharedUI/ProviderBrand.swift" \
    "$repository_dir/tools/MacAppModelProbe.swift" \
    "${package_objects[@]}" -o "$probe_output_dir/MacAppModelProbe"
"$probe_output_dir/MacAppModelProbe"
