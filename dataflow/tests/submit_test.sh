#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -f "$tmp/mvn" "$tmp/java" "$tmp/log" "$tmp/java_args" "$tmp/error"; rmdir "$tmp"' EXIT

cat >"$tmp/mvn" <<'EOF'
#!/usr/bin/env bash
echo mvn >>"$TEST_TMP/log"
EOF
cat >"$tmp/java" <<'EOF'
#!/usr/bin/env bash
echo java >>"$TEST_TMP/log"
printf '%s\n' "$@" >"$TEST_TMP/java_args"
EOF
chmod +x "$tmp/mvn" "$tmp/java"
export PATH="$tmp:$PATH" TEST_TMP="$tmp"

unset WRITE_METHOD
bash "$root/dataflow/submit.sh"
grep -Fxq -- '--writeMethod=STORAGE_WRITE_API' "$tmp/java_args"

for method in STORAGE_WRITE_API STREAMING_INSERTS FILE_LOADS; do
  WRITE_METHOD="$method" bash "$root/dataflow/submit.sh"
  grep -Fxq -- "--writeMethod=$method" "$tmp/java_args"
done

: >"$tmp/log"
if WRITE_METHOD=INVALID bash "$root/dataflow/submit.sh" 2>"$tmp/error"; then
  echo "Invalid write method was accepted" >&2
  exit 1
fi
grep -q 'Invalid WRITE_METHOD' "$tmp/error"
if [[ -s "$tmp/log" ]]; then
  echo "Invalid write method launched a command" >&2
  exit 1
fi

echo "Dataflow submission mock tests passed."
