#!/usr/bin/env bash
set -euo pipefail
project_dir=$(pwd)
test_dir=$(mktemp -d /tmp/myomarchy-qml.XXXXXX)
mkdir -m 700 "$test_dir/runtime"
ln -s /usr/share/omarchy/shell/Commons "$test_dir/Commons"
ln -s "$project_dir" "$test_dir/Plugin"
cp tests/runtime.qml "$test_dir/runtime.qml"
cp tests/responsive.qml "$test_dir/responsive.qml"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME=basic
export XDG_RUNTIME_DIR="$test_dir/runtime" XDG_CONFIG_HOME="$test_dir/config"
export MYOMARCHY_TEST_HELPER="$project_dir/tests/fake_helper.py"
export MYOMARCHY_TEST_IMAGE="$test_dir/preview.png"
unset WAYLAND_DISPLAY
result=$(timeout 15 qs -p "$test_dir/runtime.qml" 2>&1) || { printf '%s\n' "$result"; exit 1; }
printf '%s\n' "$result"
[[ "$result" == *PILOT_QML_PASSED* && "$result" != *TEST_FAILED* ]]
printf 'Preview: %s\n' "$MYOMARCHY_TEST_IMAGE"

for dimensions in 1120x740 1005x544 800x600 600x400 420x360 360x300; do
  IFS=x read -r MYOMARCHY_TEST_WIDTH MYOMARCHY_TEST_HEIGHT <<< "$dimensions"
  export MYOMARCHY_TEST_WIDTH MYOMARCHY_TEST_HEIGHT
  responsive=$(timeout 20 qs -p "$test_dir/responsive.qml" 2>&1) || { printf '%s\n' "$responsive"; exit 1; }
  printf '%s\n' "$responsive"
  [[ "$responsive" == *RESPONSIVE_QML_PASSED* && "$responsive" != *RESPONSIVE_FAILED* ]]
done
