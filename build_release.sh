#!/bin/bash
set -e
# This is a helper script used for simplifying the building of all the different
# images and publish them to DockerHub. This should be called via the
# "make release" target in the Makefile, which in turn will call this script
# with something like this:
#   ./build_release.sh "2.1.7"
#
# Input arguments:
# $1: Kea version (e.g. "2.1.7")

# Read the variable from the environment, or use the provided argument.
: ${KEA_VERSION:="${1}"}

# Function we will call to build each component.
build () {
    # $1: The Kea executable we want to build.
    # $2: Should be "" for Debian builds, and "-alpine" in case of Alpine.
    # $3: Should be "--push" when we are ready to deploy for real.
    docker buildx build -f "Dockerfile${2}" \
        --platform linux/amd64,linux/386,linux/arm64,linux/arm/v7 \
        --build-arg KEA_VERSION=${KEA_VERSION} \
        --target "${1}-target" \
        $(if [ $(( $(echo ${KEA_VERSION} | cut -d. -f 2 )%2 )) -eq 0 ]; then echo "-t jonasal/kea-${1}:$(echo ${KEA_VERSION} | cut -d. -f 1 )${2}"; fi) \
        -t "jonasal/kea-${1}:$(echo ${KEA_VERSION} | cut -d. -f 1-2 )${2}" \
        -t "jonasal/kea-${1}:$(echo ${KEA_VERSION} | cut -d. -f 1-3 )${2}" \
        ${3} \
        ./
}

# This loop will first build all the services for all operating systems, and
# when everything has been successfully built we go though everything again
# and push it to the destination repository. This way we will not end up with
# mismatching releases in case one component doesn't build correctly, and
# the cache should be present so the second iteration should be really quick.
for should_push in false true; do
    for os in "debian" "alpine"; do
        for target in "dhcp4" "dhcp4-ha" "dhcp6" "dhcp6-ha" "dhcp-ddns" "ctrl-agent" "hooks"; do
            build "${target}" "$(if [ "${os}" != "debian" ]; then echo "-${os}"; fi)" "$(if [ "${should_push}" == "true" ]; then echo "--push"; else echo "--pull"; fi)"
        done
    done
done
