#!/usr/bin/env bats
# Starts the pinned Alertmanager image with alertmanager/alertmanager.yml in a
# throwaway container, posts alerts shaped like the ones in
# prometheus/alert_rules.yml and reads back which ones it considers inhibited.
#
# An inhibit rule whose `equal` list names a label that differs between the
# two alerts (alertname, here) is valid config and `amtool check-config`
# accepts it, but it can never match: only a running Alertmanager shows that.
#
# AM_CONFIG points the suite at another config file, to check that it fails
# against a broken one.
bats_require_minimum_version 1.7.0

ROOT="$BATS_TEST_DIRNAME/.."

# need WHAT: skip when a tool is missing locally, but fail under CI, where a
# skipped suite would leave the job green without having tested anything.
need() {
  command -v "$1" >/dev/null && return 0
  if [ -n "${CI:-}" ]; then
    echo "$1 is required in CI" >&2
    return 1
  fi
  skip "$1 is not available"
}

setup_file() {
  need docker
  need jq
  need curl
  # The compose file may quote the value (image: "prom/alertmanager:v1"), so
  # strip quotes along with anything else that is not part of the reference.
  IMAGE=$(grep -oE 'prom/alertmanager:[^[:space:]]+' "$ROOT/docker-compose.yml" | head -n1 | tr -d "\"'")
  [ -n "$IMAGE" ]
  # The container user must be able to read the config.
  DIR=$(mktemp -d)
  chmod 755 "$DIR"
  cp "${AM_CONFIG:-$ROOT/alertmanager/alertmanager.yml}" "$DIR/alertmanager.yml"
  chmod 644 "$DIR/alertmanager.yml"
  CID=$(docker run -d --rm -p 127.0.0.1::9093 -v "$DIR":/etc/alertmanager:ro "$IMAGE" \
    --config.file=/etc/alertmanager/alertmanager.yml --storage.path=/tmp)
  PORT=$(docker port "$CID" 9093/tcp | head -n1 | sed 's/.*://')
  API="http://127.0.0.1:$PORT/api/v2"
  for _ in $(seq 1 50); do
    curl -fs "$API/status" >/dev/null && break
    sleep 0.2
  done
  curl -fs "$API/status" >/dev/null
  export IMAGE DIR CID PORT API
}

teardown_file() {
  [ -z "${CID:-}" ] || docker rm -f "$CID" >/dev/null 2>&1 || true
  [ -z "${DIR:-}" ] || rm -rf "$DIR"
}

# fire NAME SEVERITY INSTANCE [MOUNTPOINT]: post one firing alert. Posting the
# same labels again only refreshes it, so every test can start by posting what
# it needs and does not depend on the tests before it.
fire() {
  local labels
  labels=$(jq -n --arg a "$1" --arg s "$2" --arg i "$3" --arg m "${4:-}" \
    '{alertname:$a, severity:$s, instance:$i} + (if $m == "" then {} else {mountpoint:$m} end)')
  curl -fs -X POST -H 'Content-Type: application/json' "$API/alerts" \
    -d "[{\"labels\": $labels}]" >/dev/null
}

# inhibited_by ALERTNAME INSTANCE [MOUNTPOINT]: print the inhibitedBy list, or
# "absent" if Alertmanager does not list the alert.
inhibited_by() {
  local m="${3:-}"
  curl -fs "$API/alerts" | jq -c --arg a "$1" --arg i "$2" --arg m "$m" \
    '[.[] | select(.labels.alertname == $a and .labels.instance == $i
                   and (.labels.mountpoint // "") == $m)]
     | if length == 0 then "absent" else .[0].status.inhibitedBy end'
}

# poll COMMAND...: run until its output is neither "absent" nor, when
# WANT_INHIBITED is 1, an empty list; at most 10 tries, 0.5 s apart. The
# inhibitor ingests alerts asynchronously, so one GET can race it. Leaves the
# last output in $output.
poll() {
  local _
  for _ in $(seq 1 10); do
    output=$("$@")
    if [ "$output" != "absent" ] && { [ "${WANT_INHIBITED:-0}" != 1 ] || [ "$output" != "[]" ]; }; then
      return 0
    fi
    sleep 0.5
  done
  return 0
}

# settle_inhibition: post the critical disk alert and a warning for the same
# instance and mountpoint, and wait until the warning is reported inhibited.
# After this the inhibitor has the critical alert cached, so a negative
# assertion that follows cannot pass merely because it has not run yet.
settle_inhibition() {
  fire HostDiskSpaceCritical critical node:9100 /
  fire HostDiskSpaceLow warning node:9100 /
  WANT_INHIBITED=1 poll inhibited_by HostDiskSpaceLow node:9100 /
  [ "$output" != "[]" ] && [ "$output" != "absent" ]
}

@test "should_inhibit_the_warning_disk_alert_when_the_critical_one_fires_for_the_same_mountpoint" {
  fire HostDiskSpaceCritical critical node:9100 /
  fire HostDiskSpaceLow warning node:9100 /
  WANT_INHIBITED=1 poll inhibited_by HostDiskSpaceLow node:9100 /
  [ "$output" != "[]" ]
  [ "$output" != "absent" ]
}

@test "should_not_inhibit_the_critical_alert_itself" {
  settle_inhibition
  poll inhibited_by HostDiskSpaceCritical node:9100 /
  [ "$output" = "[]" ]
}

@test "should_not_inhibit_the_warning_for_a_different_mountpoint" {
  settle_inhibition
  fire HostDiskSpaceLow warning node:9100 /data
  poll inhibited_by HostDiskSpaceLow node:9100 /data
  [ "$output" = "[]" ]
}

@test "should_not_inhibit_the_warning_for_a_different_instance" {
  settle_inhibition
  fire HostDiskSpaceLow warning other:9100 /
  poll inhibited_by HostDiskSpaceLow other:9100 /
  [ "$output" = "[]" ]
}

@test "should_not_inhibit_unrelated_warnings_when_a_critical_alert_fires" {
  # ContainerDown is critical and has no mountpoint label; a rule that matched
  # on severity alone would swallow this warning, because a label missing on
  # both sides counts as equal.
  settle_inhibition
  fire ContainerDown critical cadvisor:8080
  fire ContainerRestartLoop warning cadvisor:8080
  poll inhibited_by ContainerRestartLoop cadvisor:8080
  [ "$output" = "[]" ]
}

@test "should_inhibit_the_slope_alert_when_the_critical_one_fires_for_the_same_mountpoint" {
  # HostDiskFillingFast is a warning too; a full disk must not page twice.
  settle_inhibition
  fire HostDiskFillingFast warning node:9100 /
  WANT_INHIBITED=1 poll inhibited_by HostDiskFillingFast node:9100 /
  [ "$output" != "[]" ]
  [ "$output" != "absent" ]
}

@test "should_not_inhibit_the_slope_alert_for_a_different_mountpoint" {
  settle_inhibition
  fire HostDiskFillingFast warning node:9100 /data
  poll inhibited_by HostDiskFillingFast node:9100 /data
  [ "$output" = "[]" ]
}
