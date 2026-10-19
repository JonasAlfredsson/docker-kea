#!/bin/sh
set -e

# Helper function used to make all logging messages look similar.
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S.000') INFO  [entrypoint] $1"
}
log "Starting Kea ${KEA_EXECUTABLE} container"

# Make sure there is no leftover from previous process if it was abruptly
# aborted (power shutdown for instance). Kea does not start if the pid file
# from the previous process still exists.
# https://github.com/JonasAlfredsson/docker-kea/pull/13#discussion_r1309289293
rm -fv "${KEA_PIDFILE_DIR:-/usr/local/var/run/kea}"/*.kea-"${KEA_EXECUTABLE}".pid

# Execute any potential shell scripts in the entrypoint.d/ folder.
find "/entrypoint.d/" -follow -type f -print | sort -V | while read -r f; do
    case "${f}" in
        *.sh)
            if [ -x "${f}" ]; then
                log "Launching ${f}";
                "${f}"
            else
                log "Ignoring ${f}, not executable";
            fi
            ;;
        *)
            log "Ignoring ${f}";;
    esac
done

# Use exec to make sure the Kea process inherits PID 1.
kea_command="/usr/local/sbin/kea-${KEA_EXECUTABLE}"
if [ "${KEA_CHANGE_USER:-false}" = "true" ]; then
    # Retain the network capabilities when executing Kea as the configured user.
    exec setpriv \
        --reuid="${KEA_USER}" \
        --regid="${KEA_GROUP:-${KEA_USER}}" \
        --init-groups \
        --inh-caps=-all,+net_raw,+net_bind_service \
        --ambient-caps=-all,+net_raw,+net_bind_service \
        "${kea_command}" "$@"
else
    exec "${kea_command}" "$@"
fi
