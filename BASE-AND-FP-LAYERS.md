# BASE-AND-FP-LAYERS.md — Decouple Domino 9.0.1 base from Fix Pack

The primary build in this repo bakes Domino 9.0.1 base **and** FP10 into a single image in one go (see `dockerfiles/domino9.0.1-fp10-ubi7/`). That's the simplest path and matches HCL's official container approach for newer versions.

But sometimes you want to **separate the base install from the Fix Pack install**. Reasons:

- "I want to test FP7, FP9, FP10 against the same base — without rebuilding 7 minutes of base install three times"
- "I only have entitlement for the base today; FP comes later"
- "We policy-require base/patch separation in CI"
- "I want to follow the traditional Domino-on-Linux mental model where you `./install` base first, then `./install -script` the FP"

This document covers the three workable approaches and their trade-offs.

## Table of contents

- [Approach A — Two layered images (recommended)](#approach-a--two-layered-images-recommended)
- [Approach B — Runtime install + docker commit](#approach-b--runtime-install--docker-commit)
- [Approach C — Persistent FP via volume (not recommended)](#approach-c--persistent-fp-via-volume-not-recommended)
- [Side-by-side comparison](#side-by-side-comparison)
- [What about no-FP-at-all? (just running 9.0.1 base)](#what-about-no-fp-at-all-just-running-901-base)

---

## Approach A — Two layered images (recommended)

You build **two separate images**:

1. `domino9:9.0.1` — base only, from `dockerfiles/domino9.0.1-base-ubi7/`
2. `domino9:9.0.1fp10` — FP10 layered on top, from `dockerfiles/domino9.0.1-fp10-on-base/`

The FP Dockerfile is a tiny derived image whose `FROM` is the base. Build:

```bash
# Step 1 — base image (~10 min first time)
cd dockerfiles/domino9.0.1-base-ubi7
cp /path/to/DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar .
docker build -t domino9:9.0.1 .

# Step 2 — FP10 layered on top (~3-4 min, base layers cached)
cd ../domino9.0.1-fp10-on-base
cp /path/to/domino901FP10_linux64_x86.tar .
docker build -t domino9:9.0.1fp10 .
```

Use `domino9:9.0.1fp10` for actual deployment.

### Pros

- **Reproducible**: `Dockerfile` defines the FP version → no drift
- **Cached base**: rebuilding a different FP only repeats the small FP layer
- **Standard docker idiom**: `FROM <base>` is how layered images are designed to work
- **Multiple FPs from one base**: build `domino9:9.0.1fp7` and `domino9:9.0.1fp10` from same `domino9:9.0.1` without re-installing the base

### Cons

- Need two `docker build` invocations and two Dockerfiles to maintain
- Final image has 1 more layer than the single-shot variant (negligible — image size ~ same)

### When to choose A

- You'll likely want to compare or roll back between FP levels
- You have CI that builds images and want efficient layer caching
- You want a clean immutable-image deployment story
- **In doubt, choose A** — it's the docker-native answer

---

## Approach B — Runtime install + docker commit

You boot the base image, `docker exec` the FP install steps interactively, then `docker commit` the changed container as a new image.

This is closest to the "在 VM 內裝 FP" mental model from bare-metal Domino administration.

### Steps

```bash
# 1. Build the base image (once)
cd dockerfiles/domino9.0.1-base-ubi7
docker build -t domino9:9.0.1 .

# 2. Boot the base container (use a name we can refer to)
docker volume create domino9-fpprep-data
docker run -d \
  --name domino9-fpprep \
  -p 11352:1352 -p 18080:80 -p 18585:8585 \
  -v domino9-fpprep-data:/local/notesdata \
  domino9:9.0.1
# Container enters setup-listener mode. Do NOT do setup wizard yet — we want
# to apply FP first so the resulting image is "9.0.1 FP10 + ready for setup".

# 3. Copy the FP tar into the container
docker cp domino901FP10_linux64_x86.tar domino9-fpprep:/tmp/

# 4. Stop the container BEFORE the FP install — FP modifies binaries that
#    the server process is using, will corrupt if hot-patched.
docker stop domino9-fpprep

# 5. Run the FP install via `docker run` against the stopped container's
#    state (use --rm and override entrypoint with /bin/bash).
docker run --rm \
  --user root \
  -v domino9-fpprep-data:/local/notesdata \
  --volumes-from domino9-fpprep \
  --entrypoint bash \
  domino9:9.0.1 \
  -c '
    set -e
    mkdir -p /tmp/fp10
    cp /tmp/domino901FP10_linux64_x86.tar /tmp/fp10/
    cd /tmp/fp10
    tar xf domino901FP10_linux64_x86.tar
    cd linux64/domino
    export NUI_NOTESDIR=/opt/ibm/domino
    ./install -script script.dat
    rm -rf /tmp/fp10
    echo "[ok] FP10 installed into /opt/ibm/domino"
  '

# Note: the above is a SIMPLIFIED illustration. The actual situation is
# more nuanced because `docker run --rm` against a STOPPED container's
# volumes is unusual. The truly clean way is:
#
#   docker start domino9-fpprep
#   docker exec --user root domino9-fpprep bash -c '...install steps...'
#
# But then the running server's binaries are being modified, which is
# risky. See "caveat 1" below.

# 6. Once FP install completed cleanly inside the container, commit to
#    a new image:
docker commit \
  --change 'LABEL fp.version="10" fp.installed_at="2026-05-21T22:00:00Z"' \
  domino9-fpprep \
  domino9:9.0.1fp10-runtime

# 7. Verify
docker images domino9
# REPOSITORY  TAG                   IMAGE ID  SIZE
# domino9     9.0.1fp10-runtime     <id>      ~1.6GB
# domino9     9.0.1                 <id>      ~1.4GB

# 8. Cleanup the prep container
docker rm domino9-fpprep
docker volume rm domino9-fpprep-data

# 9. Use the new image for actual deployment
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1fp10-runtime
```

### Caveats

1. **Server must be stopped during FP install**. FP modifies `/opt/ibm/domino/notes/latest/linux/*` — the same binaries a running server has open. Hot-patching corrupts memory mappings and crashes the server, or worse leaves it in inconsistent state. The `docker stop` step is mandatory.

2. **`docker exec` modifications are ephemeral**. If you `docker exec` install the FP into a running container and then `docker rm` that container without `docker commit`, **the FP is gone**. Next `docker run` from the original image boots back to base. This is the #1 mistake newcomers to docker make with this approach.

3. **`docker commit` is not declarative**. The resulting image has no `Dockerfile` you can re-run. Six months later, you won't easily remember the exact `docker exec` you ran. Use approach A if you care about reproducibility.

4. **Image size grows**. The FP install touches many files; the resulting overlay layer adds the deltas as a new fat layer. Image is slightly larger than approach A's equivalent.

### When to choose B

- You're prototyping / experimenting and don't need reproducibility
- You're using a legacy build pipeline that doesn't support multi-stage / FROM-chained Dockerfiles
- You explicitly want "feel like Domino-on-VM" mental model
- One-off migration from a bare-metal Domino 9.0.1 base + FP10 install

---

## Approach C — Persistent FP via volume (not recommended)

Theoretically you could mount `/opt/ibm/domino` as a volume too, so the FP files survive across container recreation:

```bash
docker volume create domino9-program
docker run ... \
  -v domino9-program:/opt/ibm/domino \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1
# Then docker exec to install FP into the volume
```

**Don't do this.** Reasons:

- Volume mount over an existing directory hides the image's `/opt/ibm/domino/` content. You'd need to populate the volume with the base install via a copy step. Operationally painful.
- Mixing "program files in volume" with "data files in volume" breaks the docker mental model where image = immutable program, volume = mutable data.
- If you `docker pull` or rebuild the base image (e.g., to pick up a UBI 7 security update), the new base's `/opt/ibm/domino` is masked by the old volume's content. You lose your security update.
- Backup / restore semantics get weird: program code is now mixed into your data backup.

Listed here for completeness only. Use A or B.

---

## Side-by-side comparison

| Aspect | A: Layered images | B: Runtime + commit | C: Volume |
|---|---|---|---|
| Reproducible | ✅ Dockerfile defines it | ❌ ad-hoc | ❌ |
| Fast multi-FP test | ✅ cached base | ❌ rebuild each time | ⚠️ ok-ish |
| docker history shows version | ✅ FP layer visible | ⚠️ only via LABEL | ❌ |
| Mental model match for Domino admin | ⚠️ "everything in Dockerfile" | ✅ "install FP into container" | ❌ |
| Standard docker idiom | ✅ | ⚠️ | ❌ |
| Recommended | **✅** | ⚠️ for one-offs | ❌ |

---

## What about no-FP-at-all? (just running 9.0.1 base)

You can absolutely deploy `domino9:9.0.1` as-is, **without** any FP. This is supported by Domino (FP is optional) but:

- The base 9.0.1 dates from 2013 and has known CVEs (Java, OpenSSL, TLS protocols) fixed in later FPs
- HCL Support boundary for 9.0.1 base (without FP10) is even more constrained than 9.0.1 FP10
- You won't get the SHA-2 / TLS 1.2 / modern CSRF fixes from FP8+

Practical recommendation: even for Dev / Test, apply at least FP10 (the final 9.x FP). The full image `dockerfiles/domino9.0.1-fp10-ubi7/` does this in one shot — use it unless you have a specific reason to keep base and FP separate.

---

## See also

- `BUILD.md` — main SOP (uses the one-shot `domino9.0.1-fp10-ubi7/` build)
- `TROUBLESHOOTING.md` §2 — why FP installer needs `-script` not `-silent`
- `TROUBLESHOOTING.md` §6 — why UBI 8 doesn't work as a base
