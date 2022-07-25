#!/bin/bash
set -eo pipefail

################################################################################
#
# This script will try to extract the version of Kea that is defined in the
# Makefile, along with composing the KEA_DL_BASE_URL variable.
#
# $1: The file to scan
#
################################################################################


version=$(sed -n -r -e 's/\s*KEA_VERSION="([1-9]+\.[0-9]+\.[0-9]+)".*$/\1/p' "${1}")

if [ -z "${version}" ]; then
    echo "Could not extract version from '${1}'"
    exit 1
fi

echo "::set-output name=APP_MAJOR::$(echo ${version} | cut -d. -f 1)"
echo "::set-output name=APP_MINOR::$(echo ${version} | cut -d. -f 1-2)"
echo "::set-output name=APP_PATCH::$(echo ${version} | cut -d. -f 1-3)"
echo "::set-output name=DL_BASE_URL::https://dl.cloudsmith.io/public/isc/kea-$(echo "${version}" | awk -F. '{print $1"-"$2}')"
