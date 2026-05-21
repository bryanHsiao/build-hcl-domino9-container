# Build context for `domino9:9.0.1` base (no Fix Pack) on RHEL UBI 7

## What this directory is for

Build a Domino **9.0.1 base** image (no FP applied). Useful when you want to:

- Decouple base from FP for clearer layering / version tracking
- Reuse one base image to test multiple FP levels (FP8, FP9, FP10)
- Reduce build context size (one less ~441 MB tar)
- Match how some shops deploy: "always start from clean base, then patch"

For the "one-shot base + FP10" image, see `../domino9.0.1-fp10-ubi7/` instead.

## Files committed here

| File | What |
|---|---|
| `Dockerfile` | Two-stage build, base 9.0.1 silent install only, no FP |
| `entrypoint.sh` | Same as the FP10 variant (first-run / configured-run detection, `DOMINO_ID_PASSWORD`) |
| `silent.properties` | Same as the FP10 variant — InstallShield Options File |
| `.gitignore` | Excludes installer media |

## Files you must add (NOT committed)

| File | Where to get |
|---|---|
| `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar` (~834 MB) | HCL FlexNet Operations Portal |

⚠️ Do not commit. Repo `.gitignore` excludes `*.tar`.

## Build

```bash
docker build -t domino9:9.0.1 .
```

## Then what?

See [../../BASE-AND-FP-LAYERS.md](../../BASE-AND-FP-LAYERS.md) for the
two recommended ways to apply a Fix Pack after this base:

- **Approach A (layered Dockerfile, recommended)** — build a derived image
  `FROM domino9:9.0.1` that just adds the FP. Reproducible.
- **Approach B (runtime install + docker commit)** — boot the base
  container, `docker exec` the FP install, `docker commit` the result.
- Plus how to choose between them + caveats.
