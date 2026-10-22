# Runbook: container log rotation (`docker/daemon.json`)

Without a cap, Docker's `json-file` driver keeps every container's log until the container is removed, and a noisy container can write more than a gigabyte a day. [`docker/daemon.json`](../../docker/daemon.json) sets the daemon default to 10 MB x 5 files per container and turns on `live-restore`, so the daemon restart that applies it does not stop the containers. Promtail ships logs to Loki, which keeps 7 days regardless of the cap. The container-log viewer (Dozzle) reads the `json-file` logs through the Docker API, so after the cap it shows at most 10 MB x 5 files per container; only Loki keeps the 7 days.

```json
{"live-restore": true, "log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "5"}}
```

**Do not copy the file into `/etc/docker/` and restart Docker.** A restart stops every container unless `live-restore` is already active in the running daemon, and it starts again any stopped container whose restart policy is `always`. The order below exists to prevent both.

## What is verified and what is not

| Claim | Status |
|---|---|
| `dockerd --validate` accepts the file; it does **not** check log-opt values or keys (it accepted `max-file` `"abc"` and an unknown key) | verified on a local dockerd; CI therefore also runs `scripts/check-daemon-json.sh` |
| The host runs Docker 29.8.1 with `LiveRestoreEnabled=false`, and its unit's `ExecReload` is `kill -s HUP $MAINPID` | read from the host |
| Sending the daemon SIGHUP re-reads `daemon.json`, and `live-restore` is among the options that reload applies (`log-driver` and `log-opts` are not: they need the restart) | documented (dockerd reference, "Daemon configuration file"); not tested here. The gate in step 4 is the control |
| Roughly 30-60 s of 404 from the reverse proxy after the restart (health resets to `starting`) | unverified; hence the curl loop in step 5 |
| At daemon start, a stopped container with any restart policy other than `no` may be started, not only `always` | from memory of the daemon's restore code, untested here; the pre-check therefore lists every non-`no` policy |
| A daemon that starts **without** `live-restore` stops the containers it finds still running | from memory of the moby code, untested here. Treated as true for the rollback |
| Existing containers keep their old log config until recreated | documented Docker behaviour (log config is fixed at container creation) |

## 0. Pick the window

Outside 00:00-01:00 UTC and 20:25-20:45 UTC (backup and nightly jobs). Announce it: public sites may blip (step 5).

## 1. Pre-checks (read-only, except the throwaway containers)

Run these from a checkout at the merged commit, so `docker/daemon.json` and `scripts/` are the reviewed ones.

```bash
# Nothing may be in the way of the install: it overwrites without a backup and
# the rollback below rewrites the file. If one exists, back it up and MERGE
# its settings into the new file instead of replacing it.
test ! -e /etc/docker/daemon.json && echo "no daemon.json: ok"

# The daemon refuses to start if an option is both a flag and in the file.
# This must print nothing.
systemctl cat docker | grep -E -- '--(live-restore|log-driver|log-opt)'

# Must print false: otherwise the gate in step 4 proves nothing.
docker info --format '{{.LiveRestoreEnabled}}'

# Stopped containers whose restart policy is anything but `no` (the check is
# on every non-`no` policy: always, unless-stopped and on-failure too).
docker ps -a --filter status=exited --filter status=created --filter status=dead --format '{{.Names}}' | xargs -r docker inspect --format '{{.Name}} {{.HostConfig.RestartPolicy.Name}}'

# Running count: write it down, step 6 compares against it
docker ps -q | wc -l

# JSON and keys, then the values dockerd does not check
sudo dockerd --validate --config-file docker/daemon.json
scripts/check-daemon-json.sh docker/daemon.json

# The options must work on the host's daemon, and a bad value must fail.
# nginx:alpine is already present; do not pull a new image for this.
docker run --rm --log-driver json-file --log-opt max-size=10m --log-opt max-file=5 nginx:alpine true
docker run --rm --log-driver json-file --log-opt max-size=10m --log-opt max-file=abc nginx:alpine true   # must FAIL
```

If the first throwaway run fails or the second one succeeds, stop: the values are not being checked the way this runbook assumes.

## 2. Stopped containers with a restart policy

A container stopped on purpose that still carries `restart: always` (or `unless-stopped`, or `on-failure`) can start at the daemon restart and at any reboot. For each one the pre-check lists with a policy other than `no`, with the owner's yes:

```bash
docker update --restart=no <name>          # reversible
docker update --restart=always <name>      # put it back later
```

A `docker compose up -d` that does not recreate the container keeps `no`; a recreate takes the compose file's policy again. Restore `always` explicitly if the compose file is not going to be recreated.

## 3. Install the file

```bash
sudo install -m 0644 docker/daemon.json /etc/docker/daemon.json
```

This is the first step that changes the host, and it is only safe after the pre-checks above came out clean.

## 4. Reload, then the gate

```bash
sudo systemctl reload docker
sleep 2
sudo journalctl -u docker --since -1min | grep -i 'reloaded configuration'
docker info --format '{{.LiveRestoreEnabled}}'
```

`reload` only sends the signal and returns, so first confirm the daemon logged that it reloaded (the `grep` must print a line; it needs `sudo` or membership of `adm`/`systemd-journal`). Then the gate must print `true`. If it prints `false`, **stop**: the daemon did not take `live-restore` from a reload, and a restart now would stop every container. Put the previous state back (`sudo rm /etc/docker/daemon.json` is safe here, and only here, because no daemon with `live-restore` is running yet) and plan a downtime window instead.

## 5. Restart, watched

In a second terminal, before the restart, a 1-second probe of two or three public hostnames (substitute your own):

```bash
while sleep 1; do for h in site-a.example site-b.example; do printf '%s %s %s\n' "$(date -u +%T)" "$h" "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "https://$h/")"; done; done
```

```bash
sudo systemctl restart docker      # `docker`, never `docker.socket`
```

Restart the service, not the socket unit: containers that mount the Docker socket keep a valid socket only while `docker.socket` is left alone.

With `live-restore` the containers keep running, but their health checks reset to `starting` and the reverse proxy may answer 404 for a while (roughly 30-60 s, unverified). That is the expected blip; anything still wrong after several minutes is not.

**If `dockerd` did not come back** (`systemctl is-active docker` does not print `active`):

```bash
sudo journalctl -u docker -n 50
```

Read why it failed, and if the file is the cause rewrite it to `{"live-restore": true}`. Then:

```bash
sudo systemctl reset-failed docker && sudo systemctl start docker
```

systemd stops retrying after `StartLimitBurst=3` starts in 60 s on this host, so `reset-failed` is needed before the next start. **Do not delete `daemon.json` here.** A daemon that starts without `live-restore` stops the containers it finds running: deleting the file in this situation is the outage the Rollback section warns about.

## 6. Verify

| Check | Command | Expect |
|---|---|---|
| Running count | `docker ps -q \| wc -l` | the number from step 1 |
| Stopped stays stopped | `docker ps -a --filter status=exited --format '{{.Names}}'` | the same list as before |
| Default driver | `docker info --format '{{.LoggingDriver}}'` | `json-file` |
| Live restore | `docker info --format '{{.LiveRestoreEnabled}}'` | `true` |
| New container gets the cap | `docker create --name logcap-check nginx:alpine && docker inspect --format '{{json .HostConfig.LogConfig}}' logcap-check; docker rm logcap-check` | `max-size` `10m`, `max-file` `5` |
| Public sites | the curl loop | 200 (or the usual redirect) again |
| Prometheus targets | the Targets page | all up |
| Daemon errors | `sudo journalctl -u docker --since '-15 min' -p err` | none |

## 7. Containers made before the change

They keep their old log config until they are recreated. Recreate stack by stack, each with a yes, using **that stack's own invocation**: its env file, its `-f` compose file, the image tag variables its deploy sets.

1. Check where the data lives: `docker inspect --format '{{.Name}} {{range .Mounts}}{{.Type}}:{{.Destination}} {{end}}' <container>`. It must be a named volume or a bind mount. `--force-recreate` keeps volumes (anonymous ones included) but loses anything written to the container's own filesystem. Some containers on a host have no mounts at all and some have anonymous volumes, so look before each one; never use `down`, `rm`, `-V` or `--renew-anon-volumes`.
2. Drift gate: the stack's own command with `up -d --no-deps <service> --dry-run` (no `--force-recreate`). For a compose file that matches what runs, every line says `Running`. Anything else (`Recreate`, `Create`) means the compose file has drifted from the running container: stop and report it.
3. Never a bare `up -d --force-recreate`: for stacks that have migration jobs it can run them again. Use `<the stack's compose command> up -d --no-deps --force-recreate <service>`; `--no-deps` limits it to the named services.
4. Check that the service is healthy before the next one.

Order:

| Wave | What | Note |
|---|---|---|
| 1 | exporters and Loki | log gaps of a few seconds |
| 2 | authentication stacks | logins fail for a few seconds while they restart |
| 3 | the big log producers | each is recreated with the cap |
| 4 | the log shipper (Promtail), **last** | its read positions live in the container's own filesystem (`/tmp/positions.yaml`). Recreating it may re-ship every log that is still uncapped from the beginning into a Loki with limited capacity (from memory, untested). Recreate it only after the producers above carry the cap, or first give its positions file a named volume |
| later, separate window | databases | restart cost is highest; do not bundle |
| natural releases | everything else | picks the cap up at its next recreate |

Progress, listing each running container's cap (an empty value means it still has the old config):

```bash
docker ps -q | xargs docker inspect --format '{{.Name}} {{index .HostConfig.LogConfig.Config "max-size"}}'
```

A stack that needs a different policy sets its own `logging:` block in compose, which wins over the daemon default.

## Rollback

**Do not delete `/etc/docker/daemon.json` while containers run under `live-restore`.** A daemon that starts without it stops the containers it finds alive (unverified here, see the table), which is a full outage.

To drop the log cap, change the file to:

```json
{"live-restore": true}
```

then `sudo systemctl reload docker` and, if the cap must go now, `sudo systemctl restart docker` (`docker`, never `docker.socket`). That restart is the same operation as step 5, so repeat the stopped-container policy checks of steps 1-2 beforehand and the curl loop and verification of steps 5-6 around it. Removing the file entirely is for a planned downtime window only.

Things that do not roll back on their own:

- Log files already written stay until the container is recreated; containers created while the cap was active keep it until then.
- An oversized log of a **stopped** container does not shrink. Truncating one is a separate step that needs the owner's explicit approval; it is not part of this change.
