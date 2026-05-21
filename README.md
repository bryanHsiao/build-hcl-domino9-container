# build-hcl-domino9-container

> **Self-build an HCL Domino 9.0.x container image** on RHEL UBI 7, validated to run in WSL2 + Docker Engine.

Verified target: **HCL Domino 9.0.1 FP10** (the final 9.x release).

---

## Why this repo exists

HCL only ships official container images for Domino 10.0.1 FP3 and newer. For organizations still running Domino 9.x and wanting to containerize for Dev/Test, migration rehearsal, or legacy-server preservation, there is no official path.

This repository documents the complete, working procedure to:

1. Build a container image of Domino 9.0.1 FP10 from HCL's silent installer
2. Boot it in `server -listen` mode for first-time Notes Admin setup
3. Join the container to an existing Domino domain as an additional server
4. Run it as a normal Domino server with HTTP / NRPC / LDAP / IMAP / POP3 / SMTP

The procedure was developed through ~20 build iterations on Windows 11 + WSL2 + Docker Engine 29.5.2 and patched against **five distinct pitfalls** that are not obvious from HCL's official documentation alone.

⚠ **Read [DISCLAIMER.md](DISCLAIMER.md) first.** You must have your own HCL Domino 9 entitlement and installer media. This repo does not distribute HCL software.

## Documentation map

| File | What's in it |
|---|---|
| [DISCLAIMER.md](DISCLAIMER.md) | HCL EULA, support boundary, scope of MIT license, EOM/EOS dates |
| [BUILD.md](BUILD.md) | Step-by-step build SOP: environment, installer media, `docker build`, first launch |
| [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md) | Driving the Notes Admin setup wizard to join a container into an existing Domino domain |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | The five non-obvious pitfalls already patched in this Dockerfile (read this even if you don't hit problems — it explains why the Dockerfile looks the way it does) |
| [DOMINOCTL.md](DOMINOCTL.md) | Optional: install Daniel Nashed's `dominoctl` host-side wrapper for `domino start / stop / status / restart` |
| [BASE-AND-FP-LAYERS.md](BASE-AND-FP-LAYERS.md) | Alternative: build a 9.0.1 base image, then apply Fix Pack as a separate layer (recommended for testing multiple FPs from one base) |
| `dockerfiles/domino9.0.1-fp10-ubi7/` | Recommended: one-shot 9.0.1 + FP10 in a single image |
| `dockerfiles/domino9.0.1-base-ubi7/` | Alternative: 9.0.1 base only, no FP |
| `dockerfiles/domino9.0.1-fp10-on-base/` | Alternative: FP10 layered on top of a `domino9:9.0.1` image |

## TL;DR for someone who already knows Domino

```bash
# 1. Get installer media from HCL FlexNet (your responsibility)
cd dockerfiles/domino9.0.1-fp10-ubi7
cp ~/Downloads/DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar  .
cp ~/Downloads/domino901FP10_linux64_x86.tar       .

# 2. Build
docker build -t domino9:9.0.1fp10 .

# 3. Run (fresh — setup wizard mode)
docker volume create domino9-data
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1fp10

# 4. From a Notes Admin client on the host:
#    serversetup.exe -remote 127.0.0.1:8585
#    -> walk through setup wizard

# 5. Stop, remove, restart with server.id password
docker rm -f domino9
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10

# 6. Verify
curl -sI http://localhost/
# HTTP/1.1 200 OK
# Server: Lotus-Domino
```

For the full walkthrough see [BUILD.md](BUILD.md) and [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md).

## The five pitfalls already patched in this Dockerfile

The Dockerfile here looks the way it does because of these. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for full root-cause analysis:

1. **RHEL UBI 7 doesn't include `hostname`** — `install.pl` triggers an `Undefined subroutine &DingDong::out` Perl error. Fix: `yum install hostname`.
2. **Fix Pack installer rejects `-silent`** — it uses `-script <file>` instead. Fix: drop `-silent` for FP install step.
3. **Bundled IBM J9 JVM has too small default heap** — Notes Admin client connection to setup wizard triggers `java.lang.OutOfMemoryError`. Fix: `sed -i` patch `serversetup` to add `-Xmx512m -Xms128m`.
4. **`notes.ini` has no `ServerName=` line in Domino 9** — entrypoint heuristic must use `^Setup=[0-9]` instead to detect "setup complete".
5. **Password-protected `server.id` hangs server boot** — need to pipe password to `server` via stdin. Fix: `DOMINO_ID_PASSWORD` env var honored by entrypoint.

## What's verified

| Aspect | Status |
|---|---|
| `docker build` on Windows 11 + WSL2 + Docker Engine 29.5.2 | ✅ Image size 1.48 GB |
| Container starts in setup-listener mode | ✅ Port 8585 |
| Notes Admin client `serversetup -remote` completes wizard | ✅ |
| Additional-server setup against existing Domino domain | ✅ `names.nsf` replication ~5-15 min |
| Container boots in normal mode after `DOMINO_ID_PASSWORD` | ✅ All tasks Started |
| HTTP 200 from host browser | ✅ `Server: Lotus-Domino` |
| Image portability (`docker save` → load on fresh distro) | ✅ ~6 minutes end-to-end |
| RHEL UBI 8 secondary build | ❌ Documented as incompatible — see TROUBLESHOOTING.md §6 |

## Build environment used during development

- Host: Windows 11
- WSL: WSL2 with isolated Ubuntu 24.04 LTS distro
- Docker: Docker Engine 29.5.2 (not Docker Desktop, though Docker Desktop should also work)
- Target image: `domino9:9.0.1fp10` (1.48 GB)

For other host environments (native Linux, Mac with Docker Desktop, etc.) the Dockerfile itself should be portable; the host-level prerequisites listed in [BUILD.md](BUILD.md) §1 may need adjusting.

## Status

Single maintainer, hobby / internal-research origin. PRs accepted but no SLA. The maintainer's primary use case is internal Dev/Test with Domino 9.0.1 FP10 — issues with other 9.0.x sub-versions may receive best-effort guidance only.

## License

MIT — for the scripts and documentation in this repository.

See [LICENSE](LICENSE). HCL Domino itself is **not** covered.
