# syntax=docker/dockerfile:1.6
# IBM Domino 9.0.1 base (no Fix Pack) — two-stage container build
#   - Base OS: RHEL UBI 7
#   - Two-stage: builder runs silent install, runtime is minimal
#   - Use this when you want to bake the FP separately, see ../../BASE-AND-FP-LAYERS.md
#
# Build context required (NOT committed):
#   DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar   — base installer (~834 MB)
#   silent.properties                    — response file (committed)
#   entrypoint.sh                        — runtime launcher (committed)
#
# Build:
#   cd dockerfiles/domino9.0.1-base-ubi7
#   docker build -t domino9:9.0.1 .
#
# Then either:
#   (A) Use as-is for development / testing 9.0.1 base
#   (B) Build a derived image FROM domino9:9.0.1 that adds a Fix Pack
#       (see ../../BASE-AND-FP-LAYERS.md for the Dockerfile recipe)

ARG UBI7_TAG=7.9

# ============================================================
# Builder stage: install Domino 9.0.1 base only
# ============================================================
FROM registry.access.redhat.com/ubi7/ubi:${UBI7_TAG} AS builder

ARG NOTES_UID=1000
ARG NOTES_GID=1000

# Packages required for Domino installer.
# Note: hostname is REQUIRED by install.pl @reqcmds — UBI 7 doesn't include it.
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
RUN mkdir -p /opt/ibm/domino /local/notesdata \
    && groupadd -g ${NOTES_GID} notes \
    && useradd  -u ${NOTES_UID} -g notes -d /local/notesdata -s /bin/bash notes \
    && chown -R notes:notes /opt/ibm/domino /local/notesdata

WORKDIR /tmp/install

COPY DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar /tmp/install/base.tar
COPY silent.properties                  /tmp/install/silent.properties

# Extract base, silent install (installer requires uid=0).
RUN tar xf base.tar \
    && cd linux64/domino \
    && ./install -silent -options /tmp/install/silent.properties \
    && cd /tmp/install \
    && rm -rf linux64 base.tar silent.properties

# Sanity check
RUN test -x /opt/ibm/domino/bin/server && echo "[builder] domino 9.0.1 base server binary OK"

# ============================================================
# Runtime stage: minimal image with installed Domino 9.0.1 base
# ============================================================
FROM registry.access.redhat.com/ubi7/ubi:${UBI7_TAG}

ARG NOTES_UID=1000
ARG NOTES_GID=1000

LABEL org.opencontainers.image.title="IBM Domino 9.0.1 base (community-built, no FP)" \
      org.opencontainers.image.description="Self-built Domino 9.0.1 base on RHEL UBI 7. No Fix Pack applied — use ../../BASE-AND-FP-LAYERS.md to layer one." \
      org.opencontainers.image.licenses="HCL EULA (Domino), Red Hat UBI EULA (base image)"

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

RUN mkdir -p /local /opt/ibm \
    && groupadd -g ${NOTES_GID} notes \
    && useradd  -u ${NOTES_UID} -g notes -d /local/notesdata -s /bin/bash notes

COPY --from=builder --chown=notes:notes /opt/ibm/domino   /opt/ibm/domino
COPY --from=builder --chown=notes:notes /local/notesdata  /local/notesdata

# Patch bundled IBM J9 JVM heap so setup wizard doesn't OOM
# (same fix as the FP10 variant — see ../../TROUBLESHOOTING.md §3).
RUN find /opt/ibm/domino -name serversetup -type f -exec \
    sed -i 's|-ss512k -Xmso5M|-ss512k -Xmso5M -Xmx512m -Xms128m|g' {} \; \
 && grep -l "Xmx512m" /opt/ibm/domino/notes/90010/linux/serversetup \
 || (echo "[error] serversetup heap patch failed" && exit 1)

COPY --chmod=755 entrypoint.sh /opt/entrypoint.sh

EXPOSE 1352 80 8585

USER notes
WORKDIR /local/notesdata
ENTRYPOINT ["/opt/entrypoint.sh"]
