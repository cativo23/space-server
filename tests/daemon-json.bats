#!/usr/bin/env bats
# Runs scripts/check-daemon-json.sh against docker/daemon.json and against
# deliberately broken copies of it.
#
# `dockerd --validate` accepts a non-numeric max-file and an unknown log-opt
# key, so the values are checked by the script, and these tests pin that.
bats_require_minimum_version 1.7.0

SCRIPT="$BATS_TEST_DIRNAME/../scripts/check-daemon-json.sh"
REAL="$BATS_TEST_DIRNAME/../docker/daemon.json"

setup() {
  CONF="$BATS_TEST_TMPDIR/daemon.json"
}

# mutate JQ_FILTER: write a copy of the real file with the filter applied.
mutate() {
  jq "$1" "$REAL" > "$CONF"
}

@test "should_accept_the_committed_daemon_json" {
  run "$SCRIPT" "$REAL"
  [ "$status" -eq 0 ]
}

@test "should_accept_other_valid_size_units_and_counts" {
  mutate '.["log-opts"]["max-size"] = "512k" | .["log-opts"]["max-file"] = "1"'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 0 ]
  mutate '.["log-opts"]["max-size"] = "1g" | .["log-opts"]["max-file"] = "30"'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 0 ]
}

@test "should_reject_a_file_that_is_not_json" {
  printf '{"live-restore": true,\n' > "$CONF"
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  [[ $output == *"not valid JSON"* ]]
}

@test "should_reject_a_missing_file" {
  run "$SCRIPT" "$BATS_TEST_TMPDIR/absent.json"
  [ "$status" -eq 64 ]
}

@test "should_reject_a_missing_argument" {
  run "$SCRIPT"
  [ "$status" -eq 64 ]
}

@test "should_reject_a_value_with_a_trailing_newline" {
  mutate '.["log-opts"]["max-size"] = "10m\n" | .["log-opts"]["max-file"] = "5\n"'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  [[ $output == *"2 problem"* ]]
}

@test "should_reject_a_max_size_without_a_unit" {
  mutate '.["log-opts"]["max-size"] = "10"'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  [[ $output == *"max-size"* ]]
}

@test "should_reject_a_max_size_with_a_bad_unit_or_garbage" {
  local bad
  for bad in 10mb abc 10M "-1m" "1.5m" "" "m" 0m 010m; do
    jq --arg v "$bad" '.["log-opts"]["max-size"] = $v' "$REAL" > "$CONF"
    run "$SCRIPT" "$CONF"
    [ "$status" -eq 1 ] || { echo "accepted max-size '$bad'"; return 1; }
  done
}

@test "should_reject_a_non_numeric_max_file" {
  mutate '.["log-opts"]["max-file"] = "abc"'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  [[ $output == *"max-file"* ]]
}

@test "should_reject_a_zero_or_negative_or_padded_max_file" {
  local bad
  for bad in 0 "-5" "05" "1.5" "" " 5"; do
    jq --arg v "$bad" '.["log-opts"]["max-file"] = $v' "$REAL" > "$CONF"
    run "$SCRIPT" "$CONF"
    [ "$status" -eq 1 ] || { echo "accepted max-file '$bad'"; return 1; }
  done
}

@test "should_reject_a_max_file_that_is_a_json_number" {
  # The daemon wants strings in log-opts; a bare number is rejected by dockerd.
  mutate '.["log-opts"]["max-file"] = 5'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
}

@test "should_reject_an_unknown_log_opt_key" {
  mutate '.["log-opts"]["max-fil"] = "5"'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  [[ $output == *"max-fil"* ]]
}

@test "should_reject_an_unknown_top_level_key" {
  mutate '.["storage-driver"] = "overlay2"'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  [[ $output == *"storage-driver"* ]]
}

@test "should_reject_a_file_without_live_restore" {
  mutate 'del(.["live-restore"])'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  [[ $output == *"live-restore"* ]]
}

@test "should_reject_live_restore_false" {
  mutate '.["live-restore"] = false'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
}

@test "should_reject_a_log_driver_other_than_json_file" {
  mutate '.["log-driver"] = "local"'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  [[ $output == *"log-driver"* ]]
}

@test "should_reject_a_file_missing_either_log_opt" {
  mutate 'del(.["log-opts"]["max-file"])'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  mutate 'del(.["log-opts"]["max-size"])'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  mutate 'del(.["log-opts"])'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
}

@test "should_report_every_problem_not_just_the_first" {
  mutate '.["log-opts"]["max-size"] = "x" | .["log-opts"]["max-file"] = "y"'
  run "$SCRIPT" "$CONF"
  [ "$status" -eq 1 ]
  [[ $output == *"max-size"* ]]
  [[ $output == *"max-file"* ]]
}
