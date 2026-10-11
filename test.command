#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
xcrun swiftc -swift-version 5 -O -D RESOURCE_AUDIT -framework AppKit -framework IOKit -framework ServiceManagement -framework SwiftUI -framework WidgetKit -import-objc-header Sources/IOReport.h -lIOReport Shared/*.swift Sources/*.swift Tests/DeviceAudit.swift -o build/DeviceAudit
build/DeviceAudit
