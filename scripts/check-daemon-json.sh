#!/usr/bin/env bash
# check-daemon-json — validate docker/daemon.json beyond what dockerd does.
#
# `dockerd --validate` checks that the file parses and that its top-level keys
# exist, but it accepts any log-opts key and any log-opts value (max-file "abc"
# and an invented key both pass). This script checks what it leaves out:
#   - the file is exactly one JSON object (dockerd rejects two documents in a
#     row, which jq alone would accept one after the other)
#   - the only top-level keys are live-restore, log-driver and log-opts
#   - live-restore is true and log-driver is "json-file"
#   - log-opts holds exactly max-size and max-file, both strings
#   - max-size is a positive integer plus a k, m or g unit (any case, as Docker
#     takes it); max-file is a positive integer
# max-size is a deliberate subset of what Docker accepts: no decimals, no `b`
# suffix and no bare bytes (a bare `10` means 10 bytes, almost never intended),
# no 0 and no leading zeros. Widen it here and in the tests if that changes.
# Every problem is printed, not just the first.
#
# Usage: check-daemon-json.sh FILE
# Exit codes: 0 ok, 1 the file is invalid, 64 usage or unreadable file, 70 jq
# is not installed (the production host has none: run this from a machine that
# does, or install jq there).
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: ${0##*/} FILE" >&2; exit 64; }
FILE=$1
[[ -r $FILE && -f $FILE ]] || { echo "${0##*/}: cannot read $FILE" >&2; exit 64; }
command -v jq >/dev/null || { echo "${0##*/}: jq is required but is not installed" >&2; exit 70; }

problems=0
fail() { echo "$FILE: $*"; problems=$((problems + 1)); }

jq -s -e 'length == 1 and (.[0] | type == "object")' "$FILE" >/dev/null 2>&1 || {
  echo "$FILE: not valid JSON (or not exactly one JSON object)"
  exit 1
}

# Keys that are not in the allowlist.
while IFS= read -r key; do
  fail "unknown top-level key: $key"
done < <(jq -r 'keys[] | select(. != "live-restore" and . != "log-driver" and . != "log-opts")' "$FILE")

jq -e '.["live-restore"] == true' "$FILE" >/dev/null || fail 'live-restore must be true'
jq -e '.["log-driver"] == "json-file"' "$FILE" >/dev/null || fail 'log-driver must be "json-file"'

if jq -e '.["log-opts"] | type == "object"' "$FILE" >/dev/null; then
  while IFS= read -r key; do
    fail "unknown log-opts key: $key"
  done < <(jq -r '.["log-opts"] | keys[] | select(. != "max-size" and . != "max-file")' "$FILE")

  # \A and \z anchor the whole string: `$` would also match before a trailing
  # newline, and a value like "10m\n" is not the exact shape we want.
  jq -e '.["log-opts"]["max-size"] | type == "string" and test("\\A[1-9][0-9]*[kKmMgG]\\z")' "$FILE" >/dev/null ||
    fail 'log-opts max-size must be a string like "10m" (positive integer, then k, m or g)'
  jq -e '.["log-opts"]["max-file"] | type == "string" and test("\\A[1-9][0-9]*\\z")' "$FILE" >/dev/null ||
    fail 'log-opts max-file must be a string holding a positive integer'
else
  fail 'log-opts must be an object with max-size and max-file'
fi

if [[ $problems -gt 0 ]]; then
  echo "$problems problem(s)"
  exit 1
fi
echo "$FILE: ok"
