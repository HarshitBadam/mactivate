#!/bin/zsh
set -euo pipefail

# Run the existing HID open probe as the current (unprivileged) user from a
# system launchd domain. This distinguishes interactive Terminal access from
# the daemon/non-Aqua context still open in docs/architecture-options.md.
#
# The job is temporary: its plist and output live under /tmp and the launchd
# registration is removed before this script exits. No capture is created and
# no persistent daemon is installed.

REPOSITORY_ROOT=${0:A:h:h}
PROBE_ROOT="$REPOSITORY_ROOT/MactuationProbe"
BINARY="$PROBE_ROOT/.build/debug/mactuation-probe"
USER_NAME=$(id -un)
USER_ID=$(id -u)
LABEL="com.mactivate.daemon-context-check.$USER_ID"
WORK_DIR=$(mktemp -d "/tmp/mactivate-daemon-check.XXXXXX")
PLIST="$WORK_DIR/$LABEL.plist"
STDOUT_PATH="$WORK_DIR/stdout.txt"
STDERR_PATH="$WORK_DIR/stderr.txt"
BOOTSTRAPPED=0

cleanup() {
  if (( BOOTSTRAPPED )); then
    sudo launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

echo "Building mactuation-probe..."
swift build --package-path "$PROBE_ROOT"

python3 - "$PLIST" "$LABEL" "$USER_NAME" "$BINARY" "$STDOUT_PATH" "$STDERR_PATH" <<'PY'
import plistlib
import sys

plist_path, label, user_name, binary, stdout_path, stderr_path = sys.argv[1:]
payload = {
    "Label": label,
    "ProgramArguments": [binary, "discover", "--json"],
    "RunAtLoad": True,
    "UserName": user_name,
    "StandardOutPath": stdout_path,
    "StandardErrorPath": stderr_path,
}
with open(plist_path, "wb") as handle:
    plistlib.dump(payload, handle)
PY

echo "Starting temporary system-domain job as $USER_NAME (uid $USER_ID)..."
sudo launchctl bootstrap system "$PLIST"
BOOTSTRAPPED=1

# The probe exits quickly. launchd creates the output files before exec, so
# their appearance is enough to avoid an arbitrary long wait.
for _ in {1..50}; do
  [[ -e "$STDOUT_PATH" || -e "$STDERR_PATH" ]] && break
  sleep 0.1
done
sleep 0.5

echo
echo "=== launchd stdout ==="
[[ -s "$STDOUT_PATH" ]] && /bin/cat "$STDOUT_PATH" || echo "(empty)"
echo
echo "=== launchd stderr ==="
[[ -s "$STDERR_PATH" ]] && /bin/cat "$STDERR_PATH" || echo "(empty)"
echo
echo "Temporary files: $WORK_DIR"
echo "Paste the complete output above back into the project session."
