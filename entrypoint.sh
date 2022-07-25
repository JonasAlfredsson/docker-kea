#!/bin/sh
set -e

# Helper function used to make all logging messages look similar.
log() {
    echo "$(date '+%Y-%M-%d %H:%M:%S.000') INFO  [entrypoint] $1"
}
log "Starting Kea ${KEA_EXECUTABLE} container"

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
exec /usr/sbin/kea-${KEA_EXECUTABLE} $@
