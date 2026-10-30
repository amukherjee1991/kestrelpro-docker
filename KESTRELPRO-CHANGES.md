# KestrelPro changes to docker-pi-hole

This is a modified version of docker-pi-hole (EUPL-1.2). The changes below were made
by the KestrelPro project; every changed upstream line is marked `kestrelpro:begin` /
`kestrelpro:end`. The original copyright and licence notices are unchanged.

## 2026-10-29: kestrelpro/2026.10.0-k0 (based on upstream 2026.10.0)

- `src/Dockerfile`
  - New default `FTL_SOURCE=pinned`: downloads FTL v6.8 and checks it against a SHA-256
    recorded in the file, instead of whatever `releases/latest` is at build time.
  - The admin UI is copied from the `kestrelpro-web` build context (the web fork) instead
    of being cloned from GitHub.
  - A directly cloned tag gets a `master` branch, as `master` builds already did, so the
    version check works when `CORE_BRANCH` is a tag.
  - Adds Python, the KestrelPro engine (`kestrelpro-engine` build context) and a
    `kestrel` user; exposes 8090.
- `src/start.sh`: starts the engine once FTL is up, and stops it before FTL.
- `src/kestrelpro.sh` (new): engine supervision, restart with backoff, nice 10,
  `oom_score_adj=1000`. FTL never waits for it; `KESTREL_ENGINE=off` disables it.
