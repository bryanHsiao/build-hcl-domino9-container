# Build context for `domino9:9.0.1fp10` on RHEL UBI 7

## What this directory is for

This is the **Docker build context** for the Domino 9.0.1 FP10 image.

## Files committed here

| File | What |
|---|---|
| `Dockerfile` | Two-stage build (builder + runtime), all 5 known pitfalls patched |
| `entrypoint.sh` | First-run vs configured-run detection, SIGTERM trap, `DOMINO_ID_PASSWORD` support |
| `silent.properties` | InstallShield Options File for the base Domino installer (`-G/-W/-P` directives) |
| `.gitignore` | Belt-and-suspenders to keep installer media and ID files out of git |

## Files you must add (NOT committed, by design)

Before `docker build .` will work, place these into this directory:

| File | Where to get |
|---|---|
| `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar` (~834 MB) | HCL FlexNet Operations Portal — "HCL Domino 9.0.1 for Linux 64-bit" |
| `domino901FP10_linux64_x86.tar` (~441 MB) | HCL FlexNet Operations Portal — "Domino 9.0.1 Fix Pack 10 for Linux 64-bit" |

⚠️ **Do not commit these `.tar` files** — they are HCL-copyrighted material under EULA. The repo's `.gitignore` excludes `*.tar` by default.

## Build

From this directory:

```bash
docker build -t domino9:9.0.1fp10 .
```

For full instructions including environment setup, see [../../BUILD.md](../../BUILD.md).

## Notes on the Dockerfile

- **Base image**: `registry.access.redhat.com/ubi7/ubi:7.9` — Red Hat's freely redistributable image of RHEL 7.9. UBI 7 is in Extended Life Support until 2028.
- **Two stages**: A "builder" stage runs the silent install (heavy, needs `tar`, `bc`, etc.) and a "runtime" stage `COPY --from=builder` to keep the final image leaner.
- **Heap patch**: A `RUN sed -i` line patches the `serversetup` script with `-Xmx512m -Xms128m` to prevent the J9 JVM OOM when remote setup wizard connects. See [../../TROUBLESHOOTING.md](../../TROUBLESHOOTING.md) §3 for why.
- **No `latest` symlink shenanigans**: The image is tagged with the explicit version. Tag `:latest` aliases to the same image.
