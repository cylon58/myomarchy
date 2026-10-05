#!/usr/bin/env bash
set -euo pipefail
project_dir=$(pwd)
test_dir=$(mktemp -d /tmp/myomarchy-qml.XXXXXX)
mkdir -m 700 "$test_dir/runtime"
ln -s /usr/share/omarchy/shell/Commons "$test_dir/Commons"
ln -s "$project_dir" "$test_dir/Plugin"
cp tests/runtime.qml "$test_dir/runtime.qml"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME=basic
export XDG_RUNTIME_DIR="$test_dir/runtime" XDG_CONFIG_HOME="$test_dir/config"
export MYOMARCHY_TEST_HELPER="$project_dir/tests/fake_helper.py"
export MYOMARCHY_TEST_IMAGE="$test_dir/preview.png"
unset WAYLAND_DISPLAY
result=$(timeout 15 qs -p "$test_dir/runtime.qml" 2>&1) || { printf '%s\n' "$result"; exit 1; }
printf '%s\n' "$result"
[[ "$result" == *PILOT_QML_PASSED* && "$result" != *TEST_FAILED* ]]
printf 'Preview: %s\n' "$MYOMARCHY_TEST_IMAGE"
