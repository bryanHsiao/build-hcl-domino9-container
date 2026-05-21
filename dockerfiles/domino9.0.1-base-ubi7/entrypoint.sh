#!/bin/bash
# Domino 9.0.1 FP10 container entrypoint
#
# Behavior contract (matches spec domino9-container-image-poc / Requirement: First-run entrypoint):
#   - notes.ini absent OR no Setup=<digits> line -> launch `server -listen 8585`
#     (await Notes Admin client to drive setup wizard remotely)
#   - notes.ini has Setup=<digits> -> launch `server` (normal mode)
#
# Why Setup= and not ServerName=:
#   Domino 9 stores the server name in MailServer= / KeyFileName_Owner= but does NOT
#   write a ServerName= line. The Setup= key is written by the wizard to record the
#   setup-complete version code (e.g. 900100). Absent = setup not done.
#
# Detection by notes.ini is more reliable than a flag file:
#   - Domino setup wizard writes notes.ini ONLY upon completion
#   - Partial setup attempts leave no notes.ini, so re-launch correctly enters listen mode
#
# To force re-setup: docker exec ... rm /local/notesdata/notes.ini (and recreate listener)

set -e

DOMINO_HOME=${DOMINO_HOME:-/opt/ibm/domino}
DOMINO_DATA=${DOMINO_DATA:-/local/notesdata}
NOTES_INI="${DOMINO_DATA}/notes.ini"

export LANG=${LANG:-en_US.UTF-8}
export LD_LIBRARY_PATH=${DOMINO_HOME}:${DOMINO_HOME}/notes/latest/linux:${LD_LIBRARY_PATH}

# Bump JVM heap so the bundled IBM J9 setup wizard can handle Swing GUI handshake
# without OutOfMemoryError. Default was ~64MB which is too small once a remote
# client connects and triggers Swing component initialization.
# JAVA_TOOL_OPTIONS is honored by IBM J9 (and OpenJ9) before any -X passed by
# the launcher script.
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--Xmx512m -Xms128m}"

cd "${DOMINO_DATA}"

# Forward SIGTERM to Domino for graceful shutdown
shutdown_handler() {
    echo "[entrypoint] SIGTERM received"
    if [ -f "$NOTES_INI" ] && grep -qE "^Setup=[0-9]" "$NOTES_INI" 2>/dev/null; then
        echo "[entrypoint] Configured server detected — sending server -q"
        "${DOMINO_HOME}/bin/server" -q || true
    fi
    wait "${SERVER_PID}" 2>/dev/null || true
    exit 0
}
trap shutdown_handler SIGTERM SIGINT

if [ -f "$NOTES_INI" ] && grep -qE "^Setup=[0-9]" "$NOTES_INI" 2>/dev/null; then
    echo "[entrypoint] ==== CONFIGURED RUN ===="
    echo "[entrypoint] notes.ini has Setup= marker, launching server normally."
    if [ -n "$DOMINO_ID_PASSWORD" ]; then
        echo "[entrypoint] Feeding server.id password from DOMINO_ID_PASSWORD env"
        # Use printf instead of echo so password without trailing newline issues are avoided
        # (server reads password ending at newline)
        printf '%s\n' "$DOMINO_ID_PASSWORD" | "${DOMINO_HOME}/bin/server" &
    else
        echo "[entrypoint] NOTE: DOMINO_ID_PASSWORD not set — server will hang if ID is encrypted."
        echo "[entrypoint] Set via docker run -e DOMINO_ID_PASSWORD=xxx if needed."
        "${DOMINO_HOME}/bin/server" &
    fi
else
    echo "[entrypoint] ==== FIRST RUN ===="
    echo "[entrypoint] No notes.ini (or no Setup= marker) — entering setup listen mode on port 8585."
    echo "[entrypoint] Connect Notes Admin client to <host>:8585 (host-mapped port: 18585) to drive setup wizard."
    echo "[entrypoint] After wizard completes, notes.ini will be written and a 'docker restart' will boot normal mode."
    "${DOMINO_HOME}/bin/server" -listen 8585 &
fi

SERVER_PID=$!
echo "[entrypoint] Server PID = ${SERVER_PID}"
wait "${SERVER_PID}"
