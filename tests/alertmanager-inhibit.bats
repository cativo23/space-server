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

setup_file() {
  command -v docker >/dev/null || skip "docker is not available"
  command -v jq >/dev/null || skip "jq is not available"
  IMAGE=$(grep -oE 'prom/alertmanager:[^[:space:]]+' "$ROOT/docker-compose.yml" | head -n1)
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

# fire NAME SEVERITY INSTANCE [MOUNTPOINT]: post one firing alert.
fire() {
  local labels
  labels=$(jq -n --arg a "$1" --arg s "$2" --arg i "$3" --arg m "${4:-}" \
    '{alertname:$a, severity:$s, instance:$i} + (if $m == "" then {} else {mountpoint:$m} end)')
  curl -fs -X POST -H 'Content-Type: application/json' "$API/alerts" \
    -d "[{\"labels\": $labels}]" >/dev/null
}

# inhibited_by ALERTNAME INSTANCE [MOUNTPOINT]: print the inhibitedBy list.
inhibited_by() {
  local m="${3:-}"
  curl -fs "$API/alerts" | jq -c --arg a "$1" --arg i "$2" --arg m "$m" \
    '[.[] | select(.labels.alertname == $a and .labels.instance == $i
                   and (.labels.mountpoint // "") == $m)] | .[0].status.inhibitedBy'
}

@test "should_inhibit_the_warning_disk_alert_when_the_critical_one_fires_for_the_same_mountpoint" {
  fire HostDiskSpaceCritical critical node:9100 /
  fire HostDiskSpaceLow warning node:9100 /
  run inhibited_by HostDiskSpaceLow node:9100 /
  [ "$status" -eq 0 ]
  [ "$output" != "[]" ]
  [ "$output" != "null" ]
}

@test "should_not_inhibit_the_critical_alert_itself" {
  run inhibited_by HostDiskSpaceCritical node:9100 /
  [ "$output" = "[]" ]
}

@test "should_not_inhibit_the_warning_for_a_different_mountpoint" {
  fire HostDiskSpaceLow warning node:9100 /data
  run inhibited_by HostDiskSpaceLow node:9100 /data
  [ "$output" = "[]" ]
}

@test "should_not_inhibit_the_warning_for_a_different_instance" {
  fire HostDiskSpaceLow warning other:9100 /
  run inhibited_by HostDiskSpaceLow other:9100 /
  [ "$output" = "[]" ]
}

@test "should_not_inhibit_unrelated_warnings_when_a_critical_alert_fires" {
  # ContainerDown is critical and has no mountpoint label; a rule that matched
  # on severity alone would swallow this warning, because a label missing on
  # both sides counts as equal.
  fire ContainerDown critical cadvisor:8080
  fire ContainerRestartLoop warning cadvisor:8080
  run inhibited_by ContainerRestartLoop cadvisor:8080
  [ "$output" = "[]" ]
}
