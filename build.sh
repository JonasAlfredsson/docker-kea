#!/bin/bash
set -e
# This is a helper script used for simplifying the building of all the different
# images locally. This is called from the Makefile, but it should not be any
# issues calling this directly either.
# Example:
#   ./build.sh "dhcp4" "2.1.7" "alpine"
#
# Input arguments:
# $1: Kea executable (valid strings: "dhcp4", "dhcp6", "ctrl-agent", "admin")
# $2: Kea version (e.g. "2.1.7")
# $3: Alpine build (omit for Debian build or provide "alpine" for Alpine build)

# Read the variables from the environment, or use the provided arguments.
: ${KEA_EXECUTABLE:="${1}"}
: ${KEA_VERSION:="${2}"}
: ${ALPINE_TAG:="${3}"}

# Feed all the relevant information to the `docker build` command, and tag it
# with something appropriate.
docker build -f Dockerfile"$(if [ -n "${ALPINE_TAG}" ]; then echo "-alpine"; fi)" \
    -t "kea-${KEA_EXECUTABLE}:local$(if [ -n "${ALPINE_TAG}" ]; then echo "-alpine"; fi)" \
    --build-arg KEA_VERSION=${KEA_VERSION} \
    --target "${KEA_EXECUTABLE}" \
    --pull \
    ./
