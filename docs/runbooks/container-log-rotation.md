# Runbook: container log rotation (`docker/daemon.json`)

Without a cap, Docker's `json-file` driver keeps every container's log until the container is removed, and a noisy container can write more than a gigabyte a day. [`docker/daemon.json`](../../docker/daemon.json) sets the daemon default to 10 MB x 5 files per container and turns on `live-restore`, so the daemon restart that applies it does not stop the containers. Promtail and Dozzle read logs through the Docker API, so their history is unaffected; Loki keeps 7 days.

```json
{"live-restore": true, "log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "5"}}
```

**Do not copy the file into `/etc/docker/` and restart Docker.** A restart stops every container unless `live-restore` is already active in the running daemon, and it starts again any stopped container whose restart policy is `always`. The order below exists to prevent both.

## What is verified and what is not

| Claim | Status |
|---|---|
| `dockerd --validate` accepts the file; it does **not** check log-opt values or keys (it accepted `max-file` `"abc"` and an unknown key) | verified on a local dockerd; CI therefore also runs `scripts/check-daemon-json.sh` |
| The host runs Docker 29.8.1 with `LiveRestoreEnabled=false`, and its unit's `ExecReload` is `kill -s HUP $MAINPID` | read from the host |
| Sending the daemon SIGHUP re-reads `daemon.json` and can switch `live-restore` on without a restart | from Docker's documentation, not tested here. The gate in step 4 is the control |
| Roughly 30-60 s of 404 from the reverse proxy after the restart (health resets to `starting`) | unverified; hence the curl loop in step 5 |
| A daemon that starts **without** `live-restore` stops the containers it finds still running | from memory of the moby code, untested here. Treated as true for the rollback |
| Existing containers keep their old log config until recreated | documented Docker behaviour (log config is fixed at container creation) |

## 0. Pick the window

Outside 00:00-01:00 UTC and 20:25-20:45 UTC (backup and nightly jobs). Announce it: public sites may blip (step 5).

## 1. Pre-checks (read-only, except the throwaway container)

```bash
# Restart policy of every stopped container: any `always` will start at the daemon restart
docker ps -a --filter status=exited --format '{{.Names}}' | xargs -r docker inspect --format '{{.Name}} {{.HostConfig.RestartPolicy.Name}}'

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

## 2. Stopped containers with `restart: always`

Some containers are stopped on purpose but still carry `restart: always`. They would start at the daemon restart (and at any reboot). For each one the pre-check lists, with the owner's yes:

```bash
docker update --restart=no <name>          # reversible
docker update --restart=always <name>      # put it back later
```

A `docker compose up -d` that does not recreate the container keeps `no`; a recreate takes the compose file's policy again. Restore `always` explicitly if the compose file is not going to be recreated.

## 3. Install the file

```bash
sudo install -m 0644 docker/daemon.json /etc/docker/daemon.json
```

## 4. Reload, then the gate

```bash
sudo systemctl reload docker
docker info --format '{{.LiveRestoreEnabled}}'
```

It must print `true`. If it prints `false`, **stop**: the daemon did not take `live-restore` from a reload, and a restart now would stop every container. Put the previous state back (`sudo rm /etc/docker/daemon.json` is safe here, because no daemon with `live-restore` is running yet) and plan a downtime window instead.

## 5. Restart, watched

In a second terminal, before the restart, a 1-second probe of two or three public hostnames (substitute your own):

```bash
while sleep 1; do for h in site-a.example site-b.example; do printf '%s %s %s\n' "$(date -u +%T)" "$h" "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "https://$h/")"; done; done
```

```bash
sudo systemctl restart docker
```

With `live-restore` the containers keep running, but their health checks reset to `starting` and the reverse proxy may answer 404 for a while (roughly 30-60 s, unverified). That is the expected blip; anything still wrong after several minutes is not.

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
| Daemon errors | `journalctl -u docker --since '-15 min' -p err` | none |

## 7. Containers made before the change

They keep their old log config until they are recreated. Recreate stack by stack, each with a yes, using **that stack's own invocation**: its env file, its `-f` compose file, the image tag variables its deploy sets.

1. Drift gate first: the stack's own command with `up -d --no-deps <service> --dry-run` (no `--force-recreate`). For a compose file that matches what runs, every line says `Running`. Anything else (`Recreate`, `Create`) means the compose file has drifted from the running container: stop and report it.
2. Never a bare `up -d --force-recreate`: for stacks that have migration jobs it can run them again. Use `<the stack's compose command> up -d --no-deps --force-recreate <service>`; `--no-deps` limits it to the named services.
3. Check that the service is healthy before the next one.

Order:

| Wave | What | Note |
|---|---|---|
| 1 | monitoring and log sidecars (exporters, Loki, Promtail) | log gaps of a few seconds |
| 2 | authentication stacks | logins fail for a few seconds while they restart |
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

then `sudo systemctl reload docker` and, if the cap must go now, `sudo systemctl restart docker` with the same curl loop and checks as above. Removing the file entirely is for a planned downtime window only.

Things that do not roll back on their own:

- Log files already written stay until the container is recreated; containers created while the cap was active keep it until then.
- An oversized log of a **stopped** container does not shrink. Truncating one is a separate step that needs the owner's explicit approval; it is not part of this change.
