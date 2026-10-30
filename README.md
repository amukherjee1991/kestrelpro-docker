# KestrelPro container

The container build of [KestrelPro](https://github.com/amukherjee1991/kestrelpro): DNS blocking
with an AI second opinion. Build and run instructions (`compose.yaml`) are in the main repository,
which builds this image together with the web interface fork and the review engine.

This is a modified version of Pi-hole's docker-pi-hole, used under the European Union Public
Licence v1.2 (see `LICENSE`). Pi-hole is a registered trademark of Pi-hole, LLC; KestrelPro is
not affiliated with or endorsed by Pi-hole, LLC. Every change is listed in
[KESTRELPRO-CHANGES.md](KESTRELPRO-CHANGES.md); changed upstream lines are marked
`kestrelpro:begin` / `kestrelpro:end`.

The upstream history is kept on purpose: it is what lets the KestrelPro commits be rebased onto
each new upstream release.
