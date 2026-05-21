# syntax=docker/dockerfile:1.6
# HCL/IBM Domino 9.0.1 FP10 — two-stage container build
#   - Base OS: RHEL UBI 7 (per design D1; avoids CentOS 7 EOL, stays in Domino 9 ABI range)
#   - Two-stage (per design D4): builder runs the install, runtime is minimal
#   - Silent install (per design D3): no TTY, no X11
#
# Build context required (NOT committed):
#   DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar   — base (834.3 MB)
#   domino901FP10_linux64_x86.tar       — FP10 patch (441.2 MB)
#   silent.properties                    — response file (committed)
#   entrypoint.sh                        — runtime launcher (committed)
#
# Build:
#   cd dockerfiles/domino9.0.1-fp10-ubi7
#   docker build -t domino9:9.0.1fp10 .
#
# Run (first time):
#   docker volume create domino9-data
#   docker run -d --name domino9 \
#     -p 1352:1352 -p 80:80 -p 8585:8585 \
#     -v domino9-data:/local/notesdata \
#     domino9:9.0.1fp10

ARG UBI7_TAG=7.9

# ============================================================
# Builder stage: install Domino 9.0.1 + apply FP10
# ============================================================
FROM registry.access.redhat.com/ubi7/ubi:${UBI7_TAG} AS builder

ARG NOTES_UID=1000
ARG NOTES_GID=1000

# Packages required for Domino installer + tar extraction.
# Note: hostname is REQUIRED by install.pl @reqcmds — UBI 7 doesn't include it by default,
#       missing it causes SysCmd::InitCmds to fail and triggers the (separate) DingDong::out undefined-sub bug.
RUN yum install -y \
        perl \
        ksh \
        libgcc \
        libstdc++ \
        glibc \
        which \
        procps-ng \
        tar \
        bc \
        hostname \
        ncurses \
    && yum clean all && rm -rf /var/cache/yum

# Create notes user/group BEFORE install (silent.properties references them).
# mkdir BEFORE useradd: avoid useradd -m parent-dir gotcha on UBI 7
RUN mkdir -p /opt/ibm/domino /local/notesdata \
    && groupadd -g ${NOTES_GID} notes \
    && useradd  -u ${NOTES_UID} -g notes -d /local/notesdata -s /bin/bash notes \
    && chown -R notes:notes /opt/ibm/domino /local/notesdata

WORKDIR /tmp/install

# COPY the installer media + response file
COPY DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar  /tmp/install/base.tar
COPY domino901FP10_linux64_x86.tar      /tmp/install/fp10.tar
COPY silent.properties                   /tmp/install/silent.properties

# Extract base, silent install (installer requires uid=0 — builder runs as root by default)
RUN tar xf base.tar \
    && cd linux64/domino \
    && ./install -silent -options /tmp/install/silent.properties \
    && cd /tmp/install \
    && rm -rf linux64 base.tar

# Extract FP10, silent install.
# FP installer's silent mode is `-script <file>` (does NOT accept `-silent` flag — usage error if passed).
# Requires NUI_NOTESDIR env var pointing to base install location.
RUN mkdir fp10 \
    && tar xf fp10.tar -C fp10 \
    && cd fp10/linux64/domino \
    && export NUI_NOTESDIR=/opt/ibm/domino \
    && ./install -script script.dat \
    && cd /tmp/install \
    && rm -rf fp10 fp10.tar silent.properties

# Sanity check: server binary exists
RUN test -x /opt/ibm/domino/bin/server && echo "[builder] domino server binary OK"

# ============================================================
# Runtime stage: minimal image with installed Domino only
# ============================================================
FROM registry.access.redhat.com/ubi7/ubi:${UBI7_TAG}

ARG NOTES_UID=1000
ARG NOTES_GID=1000

LABEL org.opencontainers.image.title="HCL Domino 9.0.1 FP10 (community-built)" \
      org.opencontainers.image.description="Self-built Domino 9.0.1 FP10 on RHEL UBI 7 for internal Dev/Test only. Not HCL-supported." \
      org.opencontainers.image.source="https://github.com/.../20260521-hcl-domino-9-build-image-container" \
      org.opencontainers.image.licenses="HCL EULA (Domino), Red Hat UBI EULA (base image)"

# Runtime-only packages (no install tooling)
RUN yum install -y \
        perl \
        ksh \
        libgcc \
        libstdc++ \
        glibc \
        procps-ng \
        which \
        hostname \
    && yum clean all && rm -rf /var/cache/yum

# Same notes user/group as builder (mkdir parents before useradd)
RUN mkdir -p /local /opt/ibm \
    && groupadd -g ${NOTES_GID} notes \
    && useradd  -u ${NOTES_UID} -g notes -d /local/notesdata -s /bin/bash notes

# Copy installed Domino + initial data dir from builder
COPY --from=builder --chown=notes:notes /opt/ibm/domino   /opt/ibm/domino
COPY --from=builder --chown=notes:notes /local/notesdata  /local/notesdata

# Patch the bundled IBM J9 JVM heap size for the setup wizard.
# Default heap (~64MB) OOMs when a remote Notes Admin client connects and
# the wizard initializes Swing GUI components. Discovered during Iter 10
# (see ralph_history.txt). Adding -Xmx512m + -Xms128m fixes it.
RUN find /opt/ibm/domino -name serversetup -type f -exec \
    sed -i 's|-ss512k -Xmso5M|-ss512k -Xmso5M -Xmx512m -Xms128m|g' {} \; \
 && grep -l "Xmx512m" /opt/ibm/domino/notes/90010/linux/serversetup \
 || (echo "[error] serversetup heap patch failed" && exit 1)

# Entrypoint
COPY --chmod=755 entrypoint.sh /opt/entrypoint.sh

# 1352 = Notes NRPC | 80 = HTTP | 8585 = remote server setup listener
EXPOSE 1352 80 8585

USER notes
WORKDIR /local/notesdata
ENTRYPOINT ["/opt/entrypoint.sh"]
