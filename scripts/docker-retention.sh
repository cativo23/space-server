#!/usr/bin/env bash
# docker-retention — keep a shared Docker host's image store and build cache
# bounded without touching anything a container or a rollback needs.
#
# Dry-run by default: prints the plan and exits. Deletes only with --apply.
#
# An image is KEPT when any of these holds (checked in this order):
#   in-use       a container uses it — running OR stopped (docker ps -a)
#   compose-ref  an `image:` line under COMPOSE_ROOTS names it (${VAR:-default}
#                resolves to its default; refs that stay unresolved are skipped)
#   protected    one of its references matches PROTECT_REGEX
#   newest-N     it is among the KEEP_LAST most recently pulled images of its
#                repository (LastTagTime, else Created). The in-use image counts
#                toward N: KEEP_LAST=3 is the current image plus 2 rollbacks.
#                A repository that only ever has one tag (`:latest`) therefore
#                keeps no rollback copy: the next pull replaces it.
#   too-young    it was pulled (LastTagTime, else Created) under MIN_AGE_HOURS ago
# Everything else is REMOVE, done with `docker image rm <reference>` — never -f,
# so the daemon itself still refuses to delete an image a container uses.
#
# Also, with --apply: dangling images older than MIN_AGE_HOURS
# (`image prune --filter until=`, which compares the image BUILD date, not the
# pull date) and build cache unused for BUILD_CACHE_UNTIL or above
# BUILD_CACHE_MAX. It never touches containers, volumes or networks, and never
# runs `system prune` or `image prune -a`.
#
# Before each removal under --apply the script looks again: it skips an image a
# container started using since the plan, one pulled again since the plan (a
# rollback pull), and any reference that no longer names the planned image (a
# tag re-pushed and pulled meanwhile). A sliver of time remains between that
# last look and the `image rm` itself; the daemon's own refusal of an image in
# use is the backstop for containers, not for a re-pulled tag.
#
# Settings come from the environment (systemd: EnvironmentFile=), flags win.
# --apply takes a lock, by default $RUNTIME_DIRECTORY/lock (systemd
# RuntimeDirectory=); outside a unit set DOCKER_RETENTION_LOCK to a private path.
#
# Exit codes: 0 ok, 1 some removals failed, 64 bad usage or configuration,
# 70 host state unreadable (docker ps/inspect failed, or containers exist but
# none resolved to an image), 75 host busy (another run, or a container
# mid-transition): retry later.
set -Eeuo pipefail

MODE=dry-run
KEEP_LAST=${KEEP_LAST:-3}
MIN_AGE_HOURS=${MIN_AGE_HOURS:-72}
PROTECT_REGEX=${PROTECT_REGEX:-}
COMPOSE_ROOTS=${COMPOSE_ROOTS:-}
BUILD_CACHE_UNTIL=${BUILD_CACHE_UNTIL:-168h}
BUILD_CACHE_MAX=${BUILD_CACHE_MAX:-2gb}
LOCK=${DOCKER_RETENTION_LOCK:-}

now() { printf '%s' "${DOCKER_RETENTION_NOW:-$(date +%s)}"; }
NOW=$(now)

usage() {
  cat <<'USAGE'
usage: docker-retention.sh [--dry-run | --apply] [--keep N] [--min-age-hours H]
  --dry-run          print what would be removed (default)
  --apply            remove it
  --keep N           newest images kept per repository, the in-use one included
                     (KEEP_LAST, default 3, min 1)
  --min-age-hours H  never remove an image pulled less than H hours ago (default 72)
env: PROTECT_REGEX, COMPOSE_ROOTS (space-separated dirs), BUILD_CACHE_UNTIL,
     BUILD_CACHE_MAX, DOCKER_RETENTION_LOCK (default $RUNTIME_DIRECTORY/lock)
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) MODE=dry-run ;;
    --apply) MODE=apply ;;
    --keep) KEEP_LAST=${2:-}; shift ;;
    --min-age-hours) MIN_AGE_HOURS=${2:-}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
  shift
done

if ! [[ "$KEEP_LAST" =~ ^[0-9]+$ ]] || ((KEEP_LAST < 1)); then echo "KEEP_LAST must be an integer >= 1" >&2; exit 64; fi
[[ "$MIN_AGE_HOURS" =~ ^[0-9]+$ ]] || { echo "MIN_AGE_HOURS must be an integer" >&2; exit 64; }

# An invalid regex makes [[ =~ ]] return 2 (a plain mismatch is 1); left alone it
# would match nothing and quietly protect nothing.
if [[ -n $PROTECT_REGEX ]]; then
  set +e; [[ "" =~ $PROTECT_REGEX ]]; rc=$?; set -e
  if ((rc == 2)); then echo "PROTECT_REGEX is not a valid extended regex: $PROTECT_REGEX" >&2; exit 64; fi
fi

# A root that is missing or unreadable would make the compose-ref rule see no
# `image:` lines at all and silently protect nothing.
if [[ -n $COMPOSE_ROOTS ]]; then
  read -r -a roots <<<"$COMPOSE_ROOTS"
  for root in "${roots[@]}"; do
    if [[ ! -d $root || ! -r $root || ! -x $root ]]; then
      echo "COMPOSE_ROOTS entry is not a readable directory: $root" >&2
      exit 64
    fi
  done
fi

log() { printf '%s\n' "$*"; }

if [[ $MODE == apply ]]; then
  if [[ -z $LOCK ]]; then
    if [[ -n ${RUNTIME_DIRECTORY:-} ]]; then
      LOCK=${RUNTIME_DIRECTORY%%:*}/lock
    else
      echo "no lock path: run through the systemd unit (RuntimeDirectory=) or set DOCKER_RETENTION_LOCK to a private file" >&2
      exit 64
    fi
  fi
  exec 9>"$LOCK"
  flock -n 9 || { log "another docker-retention run holds $LOCK; exiting"; exit 75; }
fi

# --- containers: every one, running or stopped -------------------------------
declare -A IN_USE=()
snapshot_in_use() {
  local -a ids=() busy=()
  local id state img ps_out inspect_out
  IN_USE=()
  ps_out=$(docker ps -a --no-trunc --format '{{.ID}}{{"\t"}}{{.State}}') \
    || { log "docker ps failed; refusing to judge what is unused"; exit 70; }
  while IFS=$'\t' read -r id state; do
    [[ -n $id ]] || continue
    ids+=("$id")
    case "$state" in created|restarting|removing) busy+=("$id:$state") ;; esac
  done <<<"$ps_out"

  if ((${#ids[@]} == 0)); then
    log "docker lists no containers at all; refusing to judge what is unused"
    [[ $MODE == apply ]] && exit 70
  fi
  if ((${#busy[@]})); then
    log "containers mid-transition (a deploy may be running): ${busy[*]}"
    [[ $MODE == apply ]] && exit 75
  fi
  ((${#ids[@]})) || return 0

  # Captured, not read through a process substitution, so a failure is seen.
  inspect_out=$(docker inspect --format '{{.Image}}' "${ids[@]}") \
    || { log "docker inspect failed; refusing to judge what is unused"; exit 70; }
  while read -r img; do
    if [[ -n $img ]]; then IN_USE[$img]=1; fi
  done <<<"$inspect_out"
  if ((${#IN_USE[@]} == 0)); then
    log "${#ids[@]} container(s) exist but none resolved to an image; refusing to judge what is unused"
    exit 70
  fi
}
snapshot_in_use

repo_of() {  # acme/app:v1 -> acme/app ; ghost@sha256:.. -> ghost ; host:5000/x:y -> host:5000/x
  local r=${1%@*}
  if [[ ${r##*/} == *:* ]]; then r=${r%:*}; fi
  printf '%s' "$r"
}

# --- references named by compose files ---------------------------------------
declare -A COMPOSE_REF=()
normalize_ref() {  # print the forms `docker image inspect .RepoTags` uses for this ref
  local r=$1 name digest=""
  r=${r#docker.io/library/}; r=${r#docker.io/}
  name=${r%@*}
  [[ $r == *@* ]] && digest=${r#*@}
  if [[ -n $digest ]]; then
    printf '%s@%s\n' "$(repo_of "$name")" "$digest"           # nginx:1.30@sha256:x -> nginx@sha256:x
    [[ ${name##*/} == *:* ]] && printf '%s\n' "$name"
  elif [[ ${name##*/} == *:* ]]; then
    printf '%s\n' "$name"
  else
    printf '%s:latest\n' "$name"
  fi
}
if [[ -n $COMPOSE_ROOTS ]]; then
  while IFS= read -r line; do
    ref=$(sed -E 's/^[[:space:]]*image:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^["'\'']//; s/["'\''][[:space:]]*$//' <<<"$line")
    ref=$(sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*:?-([^}]*)\}/\1/g' <<<"$ref")
    if [[ $ref == *'$'* || -z $ref ]]; then continue; fi
    while IFS= read -r n; do [[ -n $n ]] && COMPOSE_REF[$n]=1; done < <(normalize_ref "$ref")
  done < <(find "${roots[@]}" -maxdepth 4 -type f \( -name '*compose*.yml' -o -name '*compose*.yaml' \) \
             -not -path '*/node_modules/*' -not -path '*/.git/*' -print0 2>/dev/null \
           | xargs -0 -r grep -hE '^[[:space:]]*image:[[:space:]]*[^[:space:]]' 2>/dev/null || true)
fi

# --- images -------------------------------------------------------------------
to_epoch() {
  local s=${1% UTC}
  [[ -z $s || $s == 0001-01-01* || $s == '<nil>' ]] && return 1
  date -u -d "$s" +%s 2>/dev/null
}

# One image per line, fields split by '|': a whitespace separator would collapse
# the empty refs field of a dangling image and shift every later field.
IMAGE_FORMAT='{{.Id}}|{{range .RepoTags}}{{.}} {{end}}|{{.Metadata.LastTagTime}}|{{.Created}}|{{.Size}}'

declare -A REFS=() TS=() SIZE=() REASON=()
declare -A REPO_IDS=()
ls_out=$(docker image ls --no-trunc --format '{{.ID}}') \
  || { log "docker image ls failed"; exit 70; }
mapfile -t image_ids < <(sed '/^$/d' <<<"$ls_out" | sort -u)
if ((${#image_ids[@]})); then
  inspect_out=$(docker image inspect --format "$IMAGE_FORMAT" "${image_ids[@]}") \
    || { log "docker image inspect failed"; exit 70; }
  while IFS='|' read -r id refs lasttag created size; do
    [[ -n $id ]] || continue
    refs=${refs% }
    [[ -n $refs ]] || continue                   # dangling: handled by image prune below
    ts=$(to_epoch "$lasttag" || to_epoch "$created" || echo "$NOW")
    REFS[$id]=$refs TS[$id]=$ts SIZE[$id]=${size:-0}
    for r in $refs; do
      repo=$(repo_of "$r")
      [[ " ${REPO_IDS[$repo]:-} " == *" $id "* ]] || REPO_IDS[$repo]+="$id "
    done
  done <<<"$inspect_out"
fi

declare -A NEWEST=()
for repo in "${!REPO_IDS[@]}"; do
  n=0
  while read -r _ id; do
    ((++n <= KEEP_LAST)) && NEWEST[$id]=1
  done < <(for id in ${REPO_IDS[$repo]}; do printf '%s %s\n' "${TS[$id]}" "$id"; done | sort -k1,1nr -k2,2)
done

min_age_s=$((MIN_AGE_HOURS * 3600))
for id in "${!REFS[@]}"; do
  reason=""
  if [[ -n ${IN_USE[$id]:-} ]]; then reason=in-use; fi
  if [[ -z $reason ]]; then
    for r in ${REFS[$id]}; do [[ -n ${COMPOSE_REF[$r]:-} ]] && { reason=compose-ref; break; }; done
  fi
  if [[ -z $reason && -n $PROTECT_REGEX ]]; then
    for r in ${REFS[$id]}; do [[ $r =~ $PROTECT_REGEX ]] && { reason=protected; break; }; done
  fi
  [[ -z $reason && -n ${NEWEST[$id]:-} ]] && reason="newest-$KEEP_LAST"
  [[ -z $reason ]] && ((NOW - TS[$id] < min_age_s)) && reason=too-young
  REASON[$id]=${reason:-REMOVE}
done

# --- report -------------------------------------------------------------------
log "docker-retention mode=$([[ $MODE == apply ]] && echo APPLY || echo DRY-RUN) keep=$KEEP_LAST min_age=${MIN_AGE_HOURS}h images=${#REFS[@]} containers_images_in_use=${#IN_USE[@]} compose_refs=${#COMPOSE_REF[@]}"
log $'DECISION\tREASON\tAGE_D\tSIZE_MB\tREFERENCES'
remove_ids=(); remove_bytes=0
while read -r id; do
  r=${REASON[$id]}
  age_d=$(( (NOW - TS[$id]) / 86400 ))
  mb=$(( ${SIZE[$id]} / 1000000 ))
  if [[ $r == REMOVE ]]; then
    log "REMOVE"$'\t'"superseded"$'\t'"$age_d"$'\t'"$mb"$'\t'"${REFS[$id]}"
    remove_ids+=("$id"); remove_bytes=$((remove_bytes + ${SIZE[$id]}))
  else
    log "KEEP"$'\t'"$r"$'\t'"$age_d"$'\t'"$mb"$'\t'"${REFS[$id]}"
  fi
done < <(for id in "${!REFS[@]}"; do printf '%s\t%s\n' "${REFS[$id]}" "$id"; done | sort | cut -f2)

# Repositories no container uses: never removed here (newest-N keeps them) —
# listed so their owner can decide.
for repo in $(printf '%s\n' "${!REPO_IDS[@]}" | sort); do
  used=0
  for id in ${REPO_IDS[$repo]}; do [[ -n ${IN_USE[$id]:-} ]] && used=1; done
  ((used)) || log "NO-CONTAINER"$'\t'"$repo"$'\t'"(owner decides; not removed)"
done

dangling=$(docker image ls -q --no-trunc -f dangling=true | sort -u | wc -l)
log "remove: ${#remove_ids[@]} image(s), up to $((remove_bytes / 1000000)) MB (shared layers make the real gain smaller); dangling images: $dangling"
log "build cache: $(docker builder du 2>/dev/null | awk -F'\t+' '/^Total/{print $2}' | tr -d ' ') total; prune would drop entries unused > $BUILD_CACHE_UNTIL, then trim to $BUILD_CACHE_MAX"

if [[ $MODE != apply ]]; then
  log "DRY-RUN: nothing removed. Re-run with --apply to delete the REMOVE lines."
  exit 0
fi

# --- apply --------------------------------------------------------------------
# The host is read again right before each removal: a deploy or a rollback pull
# may have happened since the plan, or since the previous removal.
CUR_REFS="" CUR_PULLED=0
reread_image() {  # current references and pull time of image $1, read now
  local line lasttag created
  line=$(docker image inspect --format "$IMAGE_FORMAT" "$1" 2>/dev/null) || return 1
  [[ -n $line ]] || return 1
  IFS='|' read -r _ CUR_REFS lasttag created _ <<<"$line"
  CUR_PULLED=$(to_epoch "$lasttag" || to_epoch "$created" || now)
}

failed=0
for id in "${remove_ids[@]}"; do
  snapshot_in_use
  if [[ -n ${IN_USE[$id]:-} ]]; then log "skip (now in use): ${REFS[$id]}"; continue; fi
  if ! reread_image "$id"; then log "skip (gone): ${REFS[$id]}"; continue; fi
  if (($(now) - CUR_PULLED < min_age_s)); then log "skip (now too young): ${REFS[$id]}"; continue; fi
  for r in ${REFS[$id]}; do
    # A tag can be re-pushed and pulled between the plan and now, so that the
    # reference names a different, fresh image: remove it only while it still
    # names the image that was planned.
    if [[ " $CUR_REFS" != *" $r "* ]]; then log "skip (moved): $r"; continue; fi
    docker image rm "$r" || { log "failed: docker image rm $r"; failed=1; }
  done
done
docker image prune -f --filter "until=${MIN_AGE_HOURS}h" || failed=1
docker builder prune -f --filter "until=${BUILD_CACHE_UNTIL}" || failed=1
docker builder prune -f --max-used-space "$BUILD_CACHE_MAX" || failed=1
log "free on /: $(df -P / | awk 'NR==2{printf "%.1f GB", $4/1048576}')"
exit "$failed"
