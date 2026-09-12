#!/bin/bash
set -euo pipefail

# Run from anywhere. Override SIMULATOR_NAME for your installed simulator runtime.
qa_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
qa_simulator="${SIMULATOR_NAME:-iPhone 17 Pro}"
qa_output="${QA_OUTPUT_DIR:-$qa_project_dir/qa-artifacts/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$qa_output"
cd "$qa_project_dir"
xcodegen generate

set +e
xcodebuild -project KeJi.xcodeproj -scheme KeJi \
  -destination "platform=iOS Simulator,name=$qa_simulator" \
  -parallel-testing-enabled NO \
  -derivedDataPath "$qa_output/DerivedData" \
  -resultBundlePath "$qa_output/Results.xcresult" \
  test CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$qa_output/test.log"
qa_status=${PIPESTATUS[0]}
set -e

if [ -d "$qa_output/Results.xcresult" ]; then
  xcrun xcresulttool export attachments --path "$qa_output/Results.xcresult" \
    --output-path "$qa_output/screenshots" || true
fi
printf 'QA artifacts: %s\n' "$qa_output"
exit "$qa_status"
