#!/usr/bin/env bats
# Runs scripts/docker-retention.sh against a stub docker CLI (tests/stub/docker).
# NOW is pinned so ages are deterministic: 2026-10-22T03:00:00Z.
#
# shellcheck disable=SC2016  # the ${VAR} strings written to compose fixtures are literal on purpose
#
# bats runs each test under `set -e`, but a negated command (`! grep ...`) that
# is not the last line of a test never fails it. Negative checks therefore use
# `run !` (bats 1.5), or the lacks_* helpers that return 1 explicitly.
# bats_require_minimum_version itself only exists from bats-core 1.7.0, so that is
# the oldest bats that can run this file (CI installs v1.13.0).
bats_require_minimum_version 1.7.0

SCRIPT="$BATS_TEST_DIRNAME/../scripts/docker-retention.sh"

# has_line DECISION REASON REF: one output line carries all three.
has_line() {
  grep -qP "^$1\t$2\t.*(^|\t| )\Q$3\E( |$)" <<<"$output" || { echo "missing line: $*"; return 1; }
}
lacks_line() {
  if grep -qP "^$1\t$2\t.*(^|\t| )\Q$3\E( |$)" <<<"$output"; then echo "unexpected line: $*"; return 1; fi
}

# The calls the script makes that only read. A call that is not in this list is
# treated as mutating, so a command nobody thought of cannot slip through a
# denylist: it shows up in mutating_calls and fails the tests below.
mutating_calls() {
  local line
  while IFS= read -r line; do
    case $line in
      'ps -a --no-trunc --format '*) ;;
      'inspect --format {{.Image}} '*) ;;
      'image ls --no-trunc --format {{.ID}}') ;;
      'image ls -q --no-trunc -f dangling=true') ;;
      'image inspect --format '*) ;;
      'builder du') ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$CALLS"
}

# Under --apply the only mutating calls allowed are an unforced `image rm <one
# reference>` and the three prunes with their exact arguments.
unexpected_apply_calls() {
  mutating_calls | grep -Ev -e '^image rm [^ -][^ ]*$' \
    -e '^image prune -f --filter until=72h$' \
    -e '^builder prune -f --filter until=168h$' \
    -e '^builder prune -f --max-used-space 2gb$' || true
}

setup() {
  export FIX="$BATS_TEST_TMPDIR/fix" CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$FIX/compose/app"; : > "$CALLS"
  export PATH="$BATS_TEST_DIRNAME/stub:$PATH"
  export DOCKER_RETENTION_NOW=1792638000 KEEP_LAST=2 MIN_AGE_HOURS=72
  export COMPOSE_ROOTS="$FIX/compose" DOCKER_RETENTION_LOCK="$BATS_TEST_TMPDIR/lock"
  unset FAIL_ON PROTECT_REGEX RUNTIME_DIRECTORY XDG_RUNTIME_DIR
  # containers: one running app on v5, one STOPPED container on old v1
  printf 'c1\trunning\nc2\texited\n' > "$FIX/ps.tsv"
  printf 'c1\tsha256:v5\nc2\tsha256:v1\n' > "$FIX/ctr.tsv"
  # id | refs | LastTagTime | Created | size   (the separator is not whitespace on
  # purpose: an empty refs field, which dangling images have, must stay a field)
  {
    printf 'sha256:v1|acme/app:v1 |2026-09-01 00:00:00.366906515 +0000 UTC|2026-09-01T00:00:00.803283863Z|900000000\n'
    printf 'sha256:v2|acme/app:v2 |2026-09-10 00:00:00.366906515 +0000 UTC|2026-09-10T00:00:00.803283863Z|900000000\n'
    printf 'sha256:v3|acme/app:v3 |2026-09-20 00:00:00.366906515 +0000 UTC|2026-09-20T00:00:00.803283863Z|900000000\n'
    printf 'sha256:v4|acme/app:v4 |2026-10-01 00:00:00.366906515 +0000 UTC|2026-10-01T00:00:00.803283863Z|900000000\n'
    printf 'sha256:v5|acme/app:v5 |2026-10-10 00:00:00.366906515 +0000 UTC|2026-10-10T00:00:00.803283863Z|900000000\n'
    printf 'sha256:solo|lonely/tool:latest |2026-06-01 00:00:00.366906515 +0000 UTC|2026-06-01T00:00:00.803283863Z|500000000\n'
  } > "$FIX/images.txt"
}

# --- dry-run ------------------------------------------------------------------

@test "dry-run is the default and makes only read-only docker calls" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
  grep -q '^ps -a' "$CALLS"                    # the stub was really exercised
  [ -z "$(mutating_calls)" ]
}

@test "an explicit --dry-run makes only read-only docker calls too" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  grep -q '^ps -a' "$CALLS"
  [ -z "$(mutating_calls)" ]
}

@test "keeps the newest N per repository and the image a running container uses" {
  run "$SCRIPT"
  has_line KEEP newest-2 acme/app:v4
  has_line KEEP in-use acme/app:v5
}

@test "an image used only by a STOPPED container is kept" {
  run "$SCRIPT"
  has_line KEEP in-use acme/app:v1
  lacks_line REMOVE superseded acme/app:v1
}

@test "superseded, unused, old tags are listed for removal" {
  run "$SCRIPT"
  has_line REMOVE superseded acme/app:v2
  has_line REMOVE superseded acme/app:v3
}

@test "the only tag of a repository is never removed, only reported" {
  run "$SCRIPT"
  has_line KEEP newest-2 lonely/tool:latest
  grep -qP "^NO-CONTAINER\tlonely/tool\t" <<<"$output"
}

@test "a tag named by a compose file (default of \${VAR:-x}) is kept" {
  printf 'services:\n  a:\n    image: "${REG:-acme}/app:${TAG:-v2}"\n' > "$FIX/compose/app/compose.prod.yml"
  run "$SCRIPT"
  has_line KEEP compose-ref acme/app:v2
}

@test "PROTECT_REGEX holds a tag back" {
  PROTECT_REGEX='^acme/app:v3$' run "$SCRIPT"
  has_line KEEP protected acme/app:v3
  has_line REMOVE superseded acme/app:v2
}

@test "a tag pulled less than MIN_AGE_HOURS ago is kept even if built long ago" {
  # v2 (built in September) was re-pulled yesterday, e.g. for a rollback; v5 is still newer.
  sed -i -e 's/^\(sha256:v2|acme\/app:v2 |\)2026-09-10 00:00:00/\12026-10-21 00:00:00/' \
         -e 's/^\(sha256:v5|acme\/app:v5 |\)2026-10-10 00:00:00/\12026-10-21 12:00:00/' "$FIX/images.txt"
  KEEP_LAST=1 run "$SCRIPT"
  has_line KEEP too-young acme/app:v2
}

@test "a tag whose LastTagTime is the zero time is aged by its RFC3339 Created date" {
  # Layer-only pulls can leave LastTagTime unset; Created is then the only date. v2 was created yesterday.
  sed -i -e 's/^sha256:v2|acme\/app:v2 |[^|]*|[^|]*|/sha256:v2|acme\/app:v2 |0001-01-01 00:00:00 +0000 UTC|2026-10-21T02:30:22.68464112Z|/' \
         -e 's/^\(sha256:v5|acme\/app:v5 |\)2026-10-10 00:00:00/\12026-10-22 01:00:00/' "$FIX/images.txt"
  KEEP_LAST=1 run "$SCRIPT"
  has_line KEEP too-young acme/app:v2
  has_line REMOVE superseded acme/app:v3
}

@test "a LastTagTime in RFC3339 form (containerd hosts) is read as the pull date, not Created" {
  # v2 was built in September but pulled again yesterday: only LastTagTime says so.
  sed -i 's/^sha256:v2|acme\/app:v2 |[^|]*|/sha256:v2|acme\/app:v2 |2026-10-21T02:30:22.366906515Z|/' "$FIX/images.txt"
  sed -i 's/^\(sha256:v5|acme\/app:v5 |\)2026-10-10 00:00:00/\12026-10-22 01:00:00/' "$FIX/images.txt"
  KEEP_LAST=1 run "$SCRIPT"
  has_line KEEP too-young acme/app:v2
}

@test "a dangling image (empty refs field) is neither judged nor mistaken for a repository" {
  # What docker prints for an untagged image: refs empty, LastTagTime the zero time.
  printf 'sha256:dang||0001-01-01 00:00:00 +0000 UTC|2026-08-01T00:00:00.803283863Z|700000000\n' >> "$FIX/images.txt"
  # A second one as containerd hosts print it: a recent LastTagTime in RFC3339 form, refs empty.
  printf 'sha256:dang2||2026-10-21T22:00:00.366906515Z|2026-10-21T21:00:00.803283863Z|1\n' >> "$FIX/images.txt"
  printf 'sha256:dang\n\nsha256:dang2\n' > "$FIX/dangling.txt"     # a blank line must not count
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dangling images: 2"* ]]
  # `run` replaces $output, so judge the script's output, not that of a later command.
  [[ "$output" == *"images=6 "* ]]            # the six tagged images, not the dangling one
  [[ "$output" != *UTC* ]]                     # a shifted column would surface a timestamp word as a repository
  [[ "$output" != *sha256:dang* ]]
  [[ "$output" != *0001-01-01* ]]
}

@test "digest-pinned images group under their repository and a pinned compose ref protects them" {
  {
    printf 'sha256:g6|ghost@sha256:g6 |2026-10-21 03:00:00.366906515 +0000 UTC|2026-10-20T00:00:00.803283863Z|1\n'
    printf 'sha256:g5|ghost@sha256:g5 |2026-08-01 00:00:00.366906515 +0000 UTC|2026-08-01T00:00:00.803283863Z|1\n'
    printf 'sha256:g4|ghost@sha256:g4 |2026-07-01 00:00:00.366906515 +0000 UTC|2026-07-01T00:00:00.803283863Z|1\n'
  } >> "$FIX/images.txt"
  printf 'services:\n  g:\n    image: docker.io/library/ghost:5-alpine@sha256:g4 # old pin\n' > "$FIX/compose/app/compose.yml"
  run "$SCRIPT"
  has_line KEEP newest-2 ghost@sha256:g6
  has_line KEEP newest-2 ghost@sha256:g5
  has_line KEEP compose-ref ghost@sha256:g4
}

@test "an unresolvable \${VAR} or \${VAR:?} ref protects nothing extra and does not break the run" {
  printf 'services:\n  a:\n    image: acme/app:${TAG:?must be set}\n' > "$FIX/compose/app/compose.yml"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  has_line REMOVE superseded acme/app:v2
}

# --- startup validation -------------------------------------------------------

@test "KEEP_LAST below 1 is rejected" {
  KEEP_LAST=0 run "$SCRIPT"
  [ "$status" -eq 64 ]
}

@test "a non-numeric MIN_AGE_HOURS and an unknown flag are rejected" {
  MIN_AGE_HOURS=soon run "$SCRIPT"
  [ "$status" -eq 64 ]
  run "$SCRIPT" --nuke
  [ "$status" -eq 64 ]
}

@test "--keep and --min-age-hours without a value exit 64, not 1" {
  run "$SCRIPT" --keep
  [ "$status" -eq 64 ]
  run "$SCRIPT" --min-age-hours
  [ "$status" -eq 64 ]
  run "$SCRIPT" --apply --keep
  [ "$status" -eq 64 ]
  [ ! -s "$CALLS" ]
}

@test "an invalid PROTECT_REGEX exits 64 at startup instead of protecting nothing" {
  PROTECT_REGEX='^(acme' run "$SCRIPT" --apply
  [ "$status" -eq 64 ]
  [[ "$output" == *PROTECT_REGEX* ]]
  [ ! -s "$CALLS" ]                             # nothing was asked of docker
}

@test "a COMPOSE_ROOTS entry that is not a readable directory exits 64 instead of disabling compose-ref" {
  COMPOSE_ROOTS="$FIX/compose $FIX/not-there" run "$SCRIPT"
  [ "$status" -eq 64 ]
  [[ "$output" == *"$FIX/not-there"* ]]
  [ ! -s "$CALLS" ]
  : > "$FIX/a-file"
  COMPOSE_ROOTS="$FIX/a-file" run "$SCRIPT" --apply
  [ "$status" -eq 64 ]
  [ ! -s "$CALLS" ]
}

@test "a COMPOSE_ROOTS of only whitespace exits 64 instead of scanning the current directory" {
  COMPOSE_ROOTS="  " run "$SCRIPT"
  [ "$status" -eq 64 ]
  [ ! -s "$CALLS" ]
}

@test "an unreadable COMPOSE_ROOTS directory exits 64" {
  [ "$(id -u)" -ne 0 ] || skip "root can read anything"
  mkdir "$FIX/locked"; chmod 000 "$FIX/locked"
  COMPOSE_ROOTS="$FIX/locked" run "$SCRIPT"
  chmod 755 "$FIX/locked"
  [ "$status" -eq 64 ]
  [ ! -s "$CALLS" ]
}

# --- host state that blocks a judgement ---------------------------------------

@test "a container mid-transition stops --apply with 75 (deploy in flight)" {
  printf 'c3\trestarting\n' >> "$FIX/ps.tsv"; printf 'c3\tsha256:v5\n' >> "$FIX/ctr.tsv"
  run "$SCRIPT" --apply
  [ "$status" -eq 75 ]
  [ -z "$(mutating_calls)" ]
}

@test "docker listing no containers at all stops --apply with 70" {
  : > "$FIX/ps.tsv"
  run "$SCRIPT" --apply
  [ "$status" -eq 70 ]
  [ -z "$(mutating_calls)" ]
}

@test "containers that exist but resolve to no image exit 70, even in dry-run" {
  : > "$FIX/ctr.tsv"                            # docker inspect answers with nothing
  run "$SCRIPT"
  [ "$status" -eq 70 ]
  [ -z "$(mutating_calls)" ]
}

@test "a failing docker inspect exits 70 instead of judging every image unused" {
  FAIL_ON='inspect --format {{.Image}}' run "$SCRIPT" --apply
  [ "$status" -eq 70 ]
  [ -z "$(mutating_calls)" ]
}

@test "a failing docker image ls of the dangling images exits 70, not 1" {
  FAIL_ON='image ls -q' run "$SCRIPT"
  [ "$status" -eq 70 ]
  FAIL_ON='image ls -q' run "$SCRIPT" --apply
  [ "$status" -eq 70 ]
  [ -z "$(mutating_calls)" ]
}

# --- --apply ------------------------------------------------------------------

@test "--apply removes superseded tags by reference and nothing else" {
  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  grep -qx 'image rm acme/app:v2' "$CALLS"
  grep -qx 'image rm acme/app:v3' "$CALLS"
  run ! grep -E 'image rm .*(v1|v4|v5|lonely)' "$CALLS"
}

@test "--apply never forces an image removal" {
  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  grep -q '^image rm ' "$CALLS"
  [ -z "$(unexpected_apply_calls)" ]
}

@test "--apply issues exactly these mutating commands" {
  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  expected=$'image rm acme/app:v2\nimage rm acme/app:v3\nimage prune -f --filter until=72h\nbuilder prune -f --filter until=168h\nbuilder prune -f --max-used-space 2gb'
  [ "$(mutating_calls)" = "$expected" ]
}

@test "--apply changes nothing beyond unforced image removals and the three prunes" {
  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  [ -n "$(mutating_calls)" ]
  [ -z "$(unexpected_apply_calls)" ]
}

@test "--apply re-checks usage before every removal" {
  run "$SCRIPT" --apply
  # one view for the plan plus one per removal, so a deploy that starts mid-run is seen
  [ "$(grep -c '^ps -a' "$CALLS")" -ge 3 ]
}

@test "an image that a container started using after the plan is skipped" {
  cp "$FIX/ps.tsv" "$FIX/ps.tsv.later";   printf 'c3\trunning\n' >> "$FIX/ps.tsv.later"
  cp "$FIX/ctr.tsv" "$FIX/ctr.tsv.later"; printf 'c3\tsha256:v2\n' >> "$FIX/ctr.tsv.later"
  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip (now in use): acme/app:v2"* ]]
  run ! grep -qx 'image rm acme/app:v2' "$CALLS"
  grep -qx 'image rm acme/app:v3' "$CALLS"
}

@test "an image pulled again after the plan (a rollback pull) is skipped as too young" {
  cp "$FIX/images.txt" "$FIX/images.txt.later"
  sed -i 's/^\(sha256:v2|acme\/app:v2 |\)2026-09-10 00:00:00/\12026-10-22 02:00:00/' "$FIX/images.txt.later"
  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip (now too young): acme/app:v2"* ]]
  run ! grep -qx 'image rm acme/app:v2' "$CALLS"
  grep -qx 'image rm acme/app:v3' "$CALLS"
}

@test "a tag that moved to a new image after the plan is not removed" {
  # Between plan and apply acme/app:v2 is re-pushed and pulled: the planned image
  # sha256:v2 lost the tag (it is dangling now) and a new image, pulled a minute
  # ago, carries it. Removing "acme/app:v2" would delete the fresh image.
  cp "$FIX/images.txt" "$FIX/images.txt.later"
  sed -i 's/^sha256:v2|acme\/app:v2 |/sha256:v2|| /' "$FIX/images.txt.later"
  printf 'sha256:v2new|acme/app:v2 |2026-10-22 02:59:00.366906515 +0000 UTC|2026-10-22T02:00:00.803283863Z|900000000\n' >> "$FIX/images.txt.later"
  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip (moved): acme/app:v2"* ]]
  run ! grep -qx 'image rm acme/app:v2' "$CALLS"
  grep -qx 'image rm acme/app:v3' "$CALLS"
}

@test "only the references that still name the planned image are removed" {
  # v2 carries a second tag that moved away; its first tag still names the image.
  printf 'sha256:v2|acme/app:v2 acme/app:stable |2026-09-10 00:00:00.366906515 +0000 UTC|2026-09-10T00:00:00.803283863Z|900000000\n' \
    | cat - <(grep -v '^sha256:v2|' "$FIX/images.txt") > "$FIX/images.txt.new"
  mv "$FIX/images.txt.new" "$FIX/images.txt"
  cp "$FIX/images.txt" "$FIX/images.txt.later"
  sed -i 's/^sha256:v2|acme\/app:v2 acme\/app:stable |/sha256:v2|acme\/app:v2 |/' "$FIX/images.txt.later"
  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip (moved): acme/app:stable"* ]]
  grep -qx 'image rm acme/app:v2' "$CALLS"
  run ! grep -qx 'image rm acme/app:stable' "$CALLS"
}

@test "an image that disappeared after the plan is skipped as gone" {
  grep -v '^sha256:v2|' "$FIX/images.txt" > "$FIX/images.txt.later"
  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip (gone): acme/app:v2"* ]]
  run ! grep -qx 'image rm acme/app:v2' "$CALLS"
  grep -qx 'image rm acme/app:v3' "$CALLS"
}

@test "a failing image rm exits 1 and the loop carries on" {
  FAIL_ON='image rm acme/app:v2' run "$SCRIPT" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed: docker image rm acme/app:v2"* ]]
  grep -qx 'image rm acme/app:v3' "$CALLS"
  grep -q '^image prune' "$CALLS"
  grep -q '^builder prune' "$CALLS"
}

# --- lock ---------------------------------------------------------------------

@test "--apply exits 75 while another run holds the lock" {
  exec 8>"$DOCKER_RETENTION_LOCK"
  flock -n 8
  run "$SCRIPT" --apply
  exec 8>&-
  [ "$status" -eq 75 ]
  [ ! -s "$CALLS" ]
}

@test "--apply exits 64 when the lock file cannot be opened" {
  DOCKER_RETENTION_LOCK="$BATS_TEST_TMPDIR/no-such-dir/lock" run "$SCRIPT" --apply
  [ "$status" -eq 64 ]
  [[ "$output" == *"no-such-dir/lock"* ]]
  [ ! -s "$CALLS" ]
}

@test "the lock lives in the unit's RuntimeDirectory when no path is given" {
  unset DOCKER_RETENTION_LOCK
  mkdir "$BATS_TEST_TMPDIR/rt"
  RUNTIME_DIRECTORY="$BATS_TEST_TMPDIR/rt" run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  [ -e "$BATS_TEST_TMPDIR/rt/lock" ]
}

@test "--apply refuses to guess a lock path in a shared directory" {
  unset DOCKER_RETENTION_LOCK
  run "$SCRIPT" --apply
  [ "$status" -eq 64 ]
  [[ "$output" == *DOCKER_RETENTION_LOCK* ]]
  [ ! -s "$CALLS" ]
}

@test "the header documents exactly the exit codes the script uses" {
  codes=$(sed -n '/^# Exit codes:/,/^set -/p' "$SCRIPT" | sed 's/^# *//' | tr '\n' ' ' \
          | grep -oE '(codes:|,) [0-9]+ ' | grep -oE '[0-9]+' | tr '\n' ' ')
  [ "$codes" = "0 1 64 70 75 " ]
}
