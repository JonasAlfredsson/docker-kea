#!/bin/bash
set -eo pipefail

################################################################################
#
# This script will query the FTP repository where the Kea source files are
# located and try to parse and find the latest stable and development versions.
# If any changes are found both this script and the Makefile will be updated.
#
################################################################################

latestStable=("2" "6" "1")
stableChanged="false"
latestDev=("2" "7" "6")
devChanged="false"

# Query the FTP repository and iterate over each line of the content returned.
while read p; do
    # Try to find something that looks like a version number.
    # Currently filters out versions < 2.0.0 since they are not interesting.
    version=$(echo "${p}" | sed -n -r -e 's/^.*?href="([2-9]+\.[0-9]+\.[0-9]+)\/".*$/\1/p')
    if [ -z "${version}" ]; then
        # No version found on this line, just continue with the next one.
        continue
    fi

    # Create separate variables to make it easier to work with.
    major=$(echo ${version} | cut -d. -f 1)
    minor=$(echo ${version} | cut -d. -f 2)
    patch=$(echo ${version} | cut -d. -f 3)

    # Compare the found version with what we currently have stored.
    if [ $(( ${minor}%2 )) -eq 0 ]; then
        # Check the stable version.
        if [ "${major}" -gt "${latestStable[0]}" ]; then
            latestStable=("${major}" "${minor}" "${patch}")
            stableChanged="true"
        elif [ "${major}" -eq "${latestStable[0]}" ]; then
            if [ "${minor}" -gt "${latestStable[1]}" ]; then
                latestStable[1]="${minor}"
                latestStable[2]="${patch}"
                stableChanged="true"
            elif [ "${minor}" -eq "${latestStable[1]}" ]; then
                if [ "${patch}" -gt "${latestStable[2]}" ]; then
                    latestStable[2]="${patch}"
                    stableChanged="true"
                fi
            fi
        fi
    else
        # Check the development version.
        if [ "${major}" -gt "${latestDev[0]}" ]; then
            latestDev=("${major}" "${minor}" "${patch}")
            devChanged="true"
        elif [ "${major}" -eq "${latestDev[0]}" ]; then
            if [ "${minor}" -gt "${latestDev[1]}" ]; then
                latestDev[1]="${minor}"
                latestDev[2]="${patch}"
                devChanged="true"
            elif [ "${minor}" -eq "${latestDev[1]}" ]; then
                if [ "${patch}" -gt "${latestDev[2]}" ]; then
                    latestDev[2]="${patch}"
                    devChanged="true"
                fi
            fi
        fi
    fi
done < <(curl -sSLf https://ftp.isc.org/isc/kea/)

# Prepare some paths we are going to use.
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename ${BASH_SOURCE[0]})"
MAKEFILE_PATH="${SCRIPT_DIR}/../Makefile"

# Replace the version numbers in the relevant files, but only do one at a time
# where a new stable release has priority.
if [ "${stableChanged}" == "true" ]; then
    sed -i -E "s/^KEA_VERSION=\".*?\"$/KEA_VERSION=\"${latestStable[0]}\.${latestStable[1]}\.${latestStable[2]}\"/g" "${MAKEFILE_PATH}"
    sed -i -E "s/^latestStable=(.*?)$/latestStable=(\"${latestStable[0]}\" \"${latestStable[1]}\" \"${latestStable[2]}\")/g" "${SCRIPT_PATH}"
    echo COMMIT_MESSAGE="Kea version ${latestStable[0]}.${latestStable[1]}.${latestStable[2]} (stable)"
elif [ "${devChanged}" == "true" ]; then
    sed -i -E "s/^KEA_VERSION=\".*?\"$/KEA_VERSION=\"${latestDev[0]}\.${latestDev[1]}\.${latestDev[2]}\"/g" "${MAKEFILE_PATH}"
    sed -i -E "s/^latestDev=(.*?)$/latestDev=(\"${latestDev[0]}\" \"${latestDev[1]}\" \"${latestDev[2]}\")/g" "${SCRIPT_PATH}"
    echo COMMIT_MESSAGE="Kea version ${latestDev[0]}.${latestDev[1]}.${latestDev[2]} (development)"
fi
exit 0;
