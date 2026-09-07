#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/.state"
TEST_ROOT=$(mktemp -d "$ROOT/.state/build-identity-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/.repo/repo"
cat > "$TEST_ROOT/.repo/repo/repo" <<'EOF'
#!/usr/bin/env bash
printf 'device/opi/opi5_pro\0deadbeef\n'
printf 'packages/modules/Wifi\0cafebabe\n'
EOF
chmod +x "$TEST_ROOT/.repo/repo/repo"

first=$("$ROOT/tools/source-build-id.sh" "$TEST_ROOT" oss disabled userdebug)
second=$("$ROOT/tools/source-build-id.sh" "$TEST_ROOT" oss disabled userdebug)
[[ $first == "$second" && $first =~ ^[0-9a-f]{16}$ ]]
different=$("$ROOT/tools/source-build-id.sh" "$TEST_ROOT" oss disabled user)
[[ $first != "$different" ]]

echo "build identity tests passed"
