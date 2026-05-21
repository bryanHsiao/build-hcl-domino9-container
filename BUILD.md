# BUILD.md — Build HCL Domino 9.0.1 FP10 container image

Step-by-step SOP. Read [DISCLAIMER.md](DISCLAIMER.md) first.

## Table of contents

- [1. Prerequisites](#1-prerequisites)
- [2. Obtain installer media](#2-obtain-installer-media)
- [3. Build the image](#3-build-the-image)
- [4. First launch (setup wizard mode)](#4-first-launch-setup-wizard-mode)
- [5. Common failure modes](#5-common-failure-modes)
- [6. Backup and restore](#6-backup-and-restore)

For the additional-server setup flow against an existing Domino domain, see [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md) after step 4.

---

## 1. Prerequisites

| Item | Required version / note | Quick verify |
|---|---|---|
| Linux host or WSL2 distro | Ubuntu 22.04 / 24.04, Debian 12, RHEL 9, etc. | `cat /etc/os-release \| head -3` |
| Docker Engine | 20.10+ (29.x tested) | `docker --version` |
| Free disk | At least 5 GB | `df -h /var/lib/docker` |
| RAM available to container | At least 2 GB | `free -h` |
| HCL Domino 9 entitlement | Per HCL EULA | (you / your admin's responsibility) |
| HCL FlexNet account | Active | Browse to https://hclsoftware.flexnetoperations.com/ |

If on Windows + WSL2, create an isolated distro for this work — don't pollute your everyday WSL distro:

```powershell
# In PowerShell
mkdir C:\WSL\Ubuntu-domino9 -Force | Out-Null
wsl --install -d Ubuntu-24.04 --name Ubuntu-domino9 --location C:\WSL\Ubuntu-domino9
# Interactive prompts: pick a UNIX user (e.g. notes) and password
```

Then install Docker CE inside that distro:

```bash
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
if [ -d /run/systemd/system ]; then
  sudo systemctl enable --now docker
else
  sudo service docker start
fi
sudo usermod -aG docker $USER
# Exit, then `wsl --terminate <distro>` from PowerShell, then re-enter for group to take effect
```

Verify Docker works:

```bash
docker run --rm hello-world
```

---

## 2. Obtain installer media

You need **two files** from HCL FlexNet Operations:

| File | Approx size | Description |
|---|---|---|
| `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar` | ~834 MB | Domino 9.0.1 base for Linux x86_64 |
| `domino901FP10_linux64_x86.tar` | ~441 MB | Fix Pack 10 (the final 9.x FP) |

> **Filename notes**: "XS" in `LIN_XS_EN` is IBM xSeries (= Intel x86_64). "ZS" is zSeries (mainframe — do **not** download this). The Fix Pack uses a different naming style (lowercase, `_linux64_x86`).

### Download steps

1. Browse to https://hclsoftware.flexnetoperations.com/ and log in with your HCL account.
2. Look for "HCL Domino" → version "9.0.1".
3. Under platform filter, choose **Linux 64-bit**.
4. Download `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar`.
5. Look for the Fix Pack section (sometimes a separate "9.0.1 Fix Packs" entitlement).
6. Download `domino901FP10_linux64_x86.tar`.

If Domino 9 has been EOM'd in your account's catalog (it is EOM'd since 2024-06), HCL Support may need to re-enable historical download access.

### Place files into the build context

```bash
cd dockerfiles/domino9.0.1-fp10-ubi7

# Copy from wherever you downloaded them
cp /path/to/DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar  .
cp /path/to/domino901FP10_linux64_x86.tar       .

# Verify .gitignore is excluding these (it should be)
git status
# Expected output: tar files NOT shown as untracked
```

### (Optional) checksum your own copy

If you have a known-good SHA256 to compare against (from HCL Support / FlexNet release notes / a colleague who already downloaded):

```bash
sha256sum DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar
sha256sum domino901FP10_linux64_x86.tar
```

---

## 3. Build the image

```bash
cd dockerfiles/domino9.0.1-fp10-ubi7
docker build -t domino9:9.0.1fp10 .
```

### Expected timing (on a developer laptop, first build, no cache)

| Phase | Wall time |
|---|---|
| Pull RHEL UBI 7 base | ~30 sec |
| `yum install` build-time packages | ~30 sec |
| COPY 1.27 GB of tar into build context | ~10-30 sec (faster on native Linux than WSL `/mnt/c`) |
| Domino base silent install | ~6-7 min |
| Domino FP10 silent install (script.dat) | ~2 min |
| Runtime stage `yum install` | ~20 sec |
| `COPY --from=builder` of /opt/ibm/domino + /local/notesdata | ~20 sec |
| **Total** | **~10-12 min** |

### Build success criteria

```bash
docker images domino9
# Expected:
#   REPOSITORY   TAG          IMAGE ID    SIZE
#   domino9      9.0.1fp10    <id>        1.48GB
docker image inspect domino9:9.0.1fp10 --format '{{.Size}}'
# Expected: under 3000000000 (3 GB)
```

If build fails, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md). The most common failure modes are:

1. `redhat/ubi7` from docker.io requires auth — Dockerfile uses `registry.access.redhat.com/ubi7/ubi:7.9` (free pull) to avoid this.
2. `Undefined subroutine &DingDong::out` — caused by missing `hostname` command. Dockerfile already includes it; if you see this you may have a corrupted base image.

---

## 4. First launch (setup wizard mode)

```bash
docker volume create domino9-data

docker run -d \
  --name domino9 \
  --hostname domino9 \
  -p 1352:1352 \
  -p 80:80 \
  -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1fp10

# Watch the log
docker logs -f domino9
```

Expected log output:

```
[entrypoint] ==== FIRST RUN ====
[entrypoint] No notes.ini (or no Setup= marker) — entering setup listen mode on port 8585.
[entrypoint] Connect Notes Admin client to <host>:8585 ...
./java ... lotus.domino.setup.WizardManagerDomino -data /local/notesdata -listen 8585
Remote server setup enabled on port 8585.
The Domino setup server is now in listening mode.
```

A few `Error - can't open /proc/sys/...` warnings are expected and non-fatal — the container is non-root and can't read kernel tunables.

### Two paths from here

- **First server in a brand new domain** (uncommon if you're containerizing — usually you'd use `OneTouch` for Domino 12+ instead): use a Notes Admin client to walk the "Set up first server" wizard against port 8585. Out of scope for this SOP.
- **Additional server in an existing domain** (the recommended path): see [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md).

---

## 5. Common failure modes

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for symptom → diagnosis → fix details.

Quick summary of what to check first:

| Symptom | First thing to check |
|---|---|
| `docker build` exits at COPY step | Are both .tar files present in build context? |
| `docker build` exits during silent install | Read `/tmp/nuish.err` inside the container by `docker build` with `--progress=plain` and check stderr |
| Container exits seconds after `docker run` | `docker logs domino9` — likely password prompt for encrypted `server.id` |
| Notes Admin client "Network Communication error" | Is host port 8585 reachable? `Test-NetConnection 127.0.0.1 -Port 8585` from Windows |
| HTTP gives connection refused | Domino HTTP task not yet started — wait 60s or check `docker logs domino9 \| grep HTTP` |
| WSL2 disk exhausted | `docker system prune -a` (warning: removes images too); consider `wsl --shutdown` and free up VHDX |

---

## 6. Backup and restore

### What to back up

The container's `/local/notesdata/` directory contains all stateful Domino data:

| Path | Why it matters |
|---|---|
| `notes.ini` | Server configuration |
| `server.id` | Server identity (DO NOT lose) |
| `names.nsf` | Domino Directory (~30-200 MB depending on domain) |
| `log.nsf` | Server log database |
| `mail.box` | Inbound mail queue |
| `admin4.nsf` | Admin requests queue |
| `IBM_TECHNICAL_SUPPORT/` | NSD dumps, crash analysis |
| `*.id` files (cert.id, admin.id if present) | Other identity files |
| Any custom NSF / mail files | User data |

### Snapshot of a stopped container's data volume

```bash
docker stop domino9
docker run --rm \
  -v domino9-data:/data \
  -v "$(pwd)":/backup \
  alpine \
  tar czf /backup/domino9-data-$(date +%Y%m%d).tar.gz -C /data .
docker start domino9
```

### Restore to a fresh host

```bash
docker volume create domino9-data
docker run --rm \
  -v domino9-data:/data \
  -v /path/to/backup:/backup \
  alpine \
  tar xzf /backup/domino9-data-YYYYMMDD.tar.gz -C /data
docker run --rm --user root \
  -v domino9-data:/data \
  alpine \
  chown -R 1000:1000 /data

# Then run the container as in §4, but it will boot in CONFIGURED RUN mode
# (entrypoint detects notes.ini and skips setup listener)
docker run -d \
  --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10
```

Note: the UID/GID inside the image is 1000:1000 (user `notes`, group `notes`). When you `tar xzf`, the file ownership in the volume must match this. The `chown -R 1000:1000` step above handles that.

### Image-level backup (entire built image as a tarball)

For migration between hosts or DR snapshots:

```bash
# Export
docker save domino9:9.0.1fp10 | gzip > domino9-9.0.1fp10-image.tgz

# Import on the new host
docker load -i domino9-9.0.1fp10-image.tgz
```

The image tar contains only the immutable Docker image layers — **not** any data volume contents. Restoring on a new host requires both the image tar AND a data-volume tar.

---

_End of BUILD.md. For domain-join flow continue to [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md)._
