# Disclaimer — Important Before You Use

This repository documents **how to self-build a container image for HCL Domino 9.0.x**. It does **not** distribute HCL Domino binaries.

Read this page completely before using the build assets in this repo.

## What this repository contains

| Type | What |
|---|---|
| Build scripts | `Dockerfile`, `entrypoint.sh`, `silent.properties`, `.gitignore` |
| Documentation | `README.md`, `BUILD.md`, `ADDITIONAL-SERVER.md`, `TROUBLESHOOTING.md`, `DOMINOCTL.md`, this file |
| License | MIT (for the scripts + docs above) |

## What this repository explicitly does NOT contain

- HCL Domino installer media (any `.tar` file with installer binaries)
- HCL Domino fix pack media
- Built Docker images (`.tar` or `.tgz` of `docker save` output)
- Any `server.id`, `cert.id`, `notes.ini`, `names.nsf`, or other identity / configuration files
- Any company-specific server names, hostnames, or credentials

If you find any of the above accidentally committed, please open an issue.

## HCL Software EULA

HCL Domino 9 is **proprietary software** owned by HCL Technologies. To use the build assets in this repo legally, **you** must:

1. Have a valid HCL Domino 9 entitlement (PVU, Authorized User, or equivalent) covering the deployment you intend to run.
2. Obtain HCL Domino 9 installation media (`DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar` and the relevant Fix Pack such as `domino901FP10_linux64_x86.tar`) directly from HCL FlexNet Operations Portal:
   https://hclsoftware.flexnetoperations.com/
3. Comply with all terms of the HCL Software License Agreement applicable to your entitlement.

The MIT license on this repository covers ONLY the scripts and documentation that I (the maintainer) authored. It does **not** grant any license to HCL Domino itself.

## HCL Support Boundary

- HCL's official Docker support began with **Domino 10.0.1 FP3**.
- Domino 9.x running in a container is **"unsupported but works"**: technically functional and verified in this research, but **outside HCL's official supported configuration**.
- If you need to file an HCL Support case, HCL Support may require you to reproduce the issue on a certified bare-metal or VM platform first.

This repository is **not affiliated with HCL Technologies**.

## Domino 9 End-of-Marketing / End-of-Support

- **2024-06-01**: HCL Domino 9 entered End of Marketing.
- **2026-06-01**: HCL Domino 9 entered End of Support.

The build assets here are intended for:

- Internal Dev / Test / QA environments
- Legacy server preservation (e.g., running old NSF databases that have not been migrated)
- Migration testing (rehearsing upgrades to Domino 12/14)

They are **not recommended as a replacement for a properly supported production deployment**.

## RHEL UBI 7 Base Image

The primary build (`dockerfiles/domino9.0.1-fp10-ubi7/`) uses Red Hat Universal Base Image 7.9. UBI is freely redistributable per the [Red Hat UBI EULA](https://www.redhat.com/en/about/ubi-licensing). UBI 7 itself has passed full support and is in Extended Life Support (ELS) until 2028.

A secondary UBI 8 attempt is documented as **not directly buildable** due to Perl 5.30 namespace strictness and missing `cpio` — details in `TROUBLESHOOTING.md`.

## No Warranty

The build scripts and documentation are provided "AS IS" under the MIT License. Use at your own risk. The maintainer has run them successfully against Domino 9.0.1 FP10 on Windows 11 + WSL2 + Docker Engine 29.5.2, but cannot guarantee success in other environments or with other versions.

## Reporting Issues

If you find bugs in the build scripts or documentation, please open an issue on this repository. For HCL Domino product bugs, contact HCL Support through the normal channels (you will need your entitlement information).
