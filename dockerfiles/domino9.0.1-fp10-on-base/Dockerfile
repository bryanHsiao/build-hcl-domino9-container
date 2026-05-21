# syntax=docker/dockerfile:1.6
# FP10 layered on top of an existing `domino9:9.0.1` base image
#
# Prereq: you have already built `domino9:9.0.1` (see ../domino9.0.1-base-ubi7/).
#
# Build context required:
#   domino901FP10_linux64_x86.tar  — FP10 patch (~441 MB)
#
# Build:
#   docker build -t domino9:9.0.1fp10 .

ARG BASE_IMAGE=domino9:9.0.1
FROM ${BASE_IMAGE}

# FP install needs root + matching install user.
USER root

# COPY FP tar into a temp dir
WORKDIR /tmp/fp10
COPY domino901FP10_linux64_x86.tar /tmp/fp10/fp10.tar

# Extract + silent install FP.
# FP installer's silent mode is `-script <file>` (does NOT accept `-silent`).
# Requires NUI_NOTESDIR env var pointing to existing base install.
RUN tar xf fp10.tar \
    && cd linux64/domino \
    && export NUI_NOTESDIR=/opt/ibm/domino \
    && ./install -script script.dat \
    && cd /tmp/fp10 \
    && rm -rf linux64 fp10.tar

# Sanity check — confirm version files updated
RUN test -f /opt/ibm/domino/notes/latest/linux/901FP10/serversetup \
        || test -d /opt/ibm/domino/notes/latest/linux/901FP10 \
        && echo "[fp10] patched OK"

# Re-patch heap on the FP-version serversetup (FP may have its own copy)
RUN find /opt/ibm/domino -name serversetup -type f -exec \
    sed -i 's|-ss512k -Xmso5M -Xmx512m -Xms128m|-ss512k -Xmso5M -Xmx512m -Xms128m|g; s|-ss512k -Xmso5M\([^-]\)|-ss512k -Xmso5M -Xmx512m -Xms128m\1|g' {} \;

# Cleanup + drop back to notes user
WORKDIR /local/notesdata
USER notes
