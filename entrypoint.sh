#!/bin/sh
set -e

# Helper function used to make all logging messages look similar.
log() {
    echo "$(date '+%Y-%M-%d %H:%M:%S.000') INFO  [entrypoint] $1"
}
log "Starting Kea ${KEA_EXECUTABLE} container"

# Make sure there is no leftover from previous process if it was abruptly aborted (power shutdown for instance).
# Kea does not restart if the pid file from the previous process still exists. This ensures that it can restart
# without any issue.
rm -f /usr/local/var/run/kea/dhcp4.kea-dhcp4.pid

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

# Feed all the command parameters directly to the defined executable.
exec /usr/local/sbin/kea-${KEA_EXECUTABLE} $@
