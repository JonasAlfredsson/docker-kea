#!/usr/bin/env bash
set -Eeuo pipefail

# Verify a DISCOVER/OFFER exchange, not a complete REQUEST/ACK lease acquisition.
# Run with the newly built image, for example: bash test_dhcp4.sh kea-dhcp4:local.
CLIENT_IMAGE="jonasal/network-tools:latest"
SERVER_IMAGE="${1:-}"

# Docker assigns container addresses in the upper half of the subnet. Kea offers
# addresses .10-.20 in the lower half, so the two allocators cannot collide.
# Address and pool values intentionally repeat in test_dhcp4.json and below;
# update all matching values in this folder together when changing the network.
SERVER_IP="192.0.2.130"
CLIENT_IP="192.0.2.131"
CLIENT_MAC="de:ad:c0:de:ca:fe"
NETWORK_SUBNET="192.0.2.0/24"
NETWORK_IP_RANGE="192.0.2.128/25"
OFFER_TIMEOUT=10s
RESOURCE_LABEL="org.docker-kea.dhcp4-test"

# Check prerequisites before creating resources or downloading the client image.
if [[ -z "$SERVER_IMAGE" || "$#" -ne 1 ]]; then
	printf 'Usage: %s <kea-dhcp4-image>\n' "$0" >&2
	exit 2
fi

for required_command in docker timeout awk grep mktemp cp dirname; do
	if ! command -v "$required_command" >/dev/null 2>&1; then
		printf 'Required command not found: %s\n' "$required_command" >&2
		exit 2
	fi
done

# Resolve companion files relative to this script, not the callers working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for companion_file in test_dhcp4.json test_dhcp4_logs.awk test_dhcp4_client.awk; do
	if [[ ! -r "$SCRIPT_DIR/$companion_file" ]]; then
		printf 'Required test file is not readable: %s\n' "$SCRIPT_DIR/$companion_file" >&2
		exit 2
	fi
done

if ! docker info >/dev/null 2>&1; then
	printf 'The Docker daemon is unavailable.\n' >&2
	exit 2
fi

# Give this invocation unique names and an ownership label. Cleanup uses the label
# as well as the name, so it cannot remove an unrelated container or network.
WORK_DIR="$(mktemp -d)"
RESOURCE_TOKEN="${WORK_DIR##*/}"
NETWORK_NAME="kea-dhcp4-test-${RESOURCE_TOKEN}"
SERVER_NAME="kea-dhcp4-server-${RESOURCE_TOKEN}"
CLIENT_NAME="kea-dhcp4-client-${RESOURCE_TOKEN}"

# Return whether a named Docker resource carries this run's ownership label.
#
# Arguments:
#   $1: The resource type (network or container)
#   $2: The resource's Docker name
#
# Returns: 0 if the resource is owned by this run, 1 otherwise.
owns_resource() {
	local resource_type="$1"
	local resource_name="$2"
	local resource_label
	if [[ "$resource_type" == network ]]; then
		resource_label="$(docker network inspect --format "{{ index .Labels \"${RESOURCE_LABEL}\" }}" "$resource_name" 2>/dev/null || true)"
	else
		resource_label="$(docker inspect --format "{{ index .Config.Labels \"${RESOURCE_LABEL}\" }}" "$resource_name" 2>/dev/null || true)"
	fi
	[[ "$resource_label" == "$RESOURCE_TOKEN" ]]
}

# Print diagnostics, remove only resources labeled by this run, and preserve failures.
#
# Arguments:
#   None; the EXIT trap provides the incoming exit status through $?
#
# Output:
#   Container logs and cleanup diagnostics on stderr; no stdout data
#
# Returns: Does not return; exits with the incoming status, or 1 if a Docker
#   cleanup error occurs after an otherwise successful run.
cleanup() {
	local exit_code="$?"
	local cleanup_failed=0
	local container_name
	trap - EXIT INT TERM

	# Keep diagnostic output even on success. A failed or timed-out client remains
	# available for docker logs until it is removed here.
	for container_name in "$CLIENT_NAME" "$SERVER_NAME"; do
		if owns_resource container "$container_name"; then
			printf '\n--- Logs: %s ---\n' "$container_name" >&2
			docker logs "$container_name" >&2 || cleanup_failed=1
			docker rm --force "$container_name" >/dev/null || cleanup_failed=1
		fi
	done

	# Disconnect both containers before deleting the network and temporary config.
	if owns_resource network "$NETWORK_NAME"; then
		docker network rm "$NETWORK_NAME" >/dev/null || cleanup_failed=1
	fi
	rm -rf "$WORK_DIR"

	# A cleanup error must not hide the original test failure or silently pass CI.
	if (( cleanup_failed != 0 )); then
		printf 'One or more DHCP test resources could not be cleaned up.\n' >&2
		(( exit_code != 0 )) || exit_code=1
	fi
	exit "$exit_code"
}

# Convert Nmap's broadcast-script output into four unambiguous response fields.
#
# Arguments:
#   $1: The path to the captured DHCP client's Nmap output file
#
# Output:
#   One newline-terminated, tab-separated stdout line containing the interface,
#   offered IPv4 address, DHCP message type, and server identifier, in that order
#
# Returns: 0 for exactly one response containing each required field once,
#   1 for missing or duplicate fields/responses, or nonzero for AWK/file errors.
parse_client_response() {
	awk -f "$SCRIPT_DIR/test_dhcp4_client.awk" "$1"
}

# Confirm Kea logged a matching DISCOVER, offer, and OFFER send for one transaction.
#
# Arguments:
#   $1: The path to the captured Kea container logs
#   $2: The offered IPv4 address received by the client
#
# Output:
#   None for a match or mismatch; AWK/file errors may produce stderr diagnostics
#
# Returns: 0 for one matching lease offer, DISCOVER, and OFFER send for the same
#   transaction with no send failure, 1 for a mismatch, or nonzero for AWK/file errors.
verify_server_logs() {
	awk -v mac="$CLIENT_MAC" -v offered_ip="$2" -v server_ip="$SERVER_IP" \
		-f "$SCRIPT_DIR/test_dhcp4_logs.awk" "$1"
}

# Every normal exit and interrupt goes through cleanup, including partial setup.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Refuse name collisions before starting. Labels provide a second safety check
# during cleanup, including a resource created by another process after this check.
for resource_name in "$NETWORK_NAME" "$SERVER_NAME" "$CLIENT_NAME"; do
	if docker inspect "$resource_name" >/dev/null 2>&1 || docker network inspect "$resource_name" >/dev/null 2>&1; then
		printf 'Refusing to use existing Docker resource: %s\n' "$resource_name" >&2
		exit 1
	fi
done

# Pull before starting Kea so registry delays cannot consume the DHCP timeout.
# The script-help check confirms that the client image contains the required NSE script.
printf 'Pulling DHCP test client image %s\n' "$CLIENT_IMAGE"
timeout --signal=TERM --kill-after=5s 120s docker pull "$CLIENT_IMAGE"
timeout --signal=TERM --kill-after=5s 30s docker run --rm "$CLIENT_IMAGE" nmap --script-help broadcast-dhcp-discover >/dev/null

# Use the simple example's lease timers, but a dedicated subnet and no persistent
# leases. INFO logging includes the three packet/lease events asserted below.
# Copy the neighboring fixture into the temporary config mount, leaving repository
# files and the interactive example untouched.
cp "$SCRIPT_DIR/test_dhcp4.json" "$WORK_DIR/dhcp4.json"

# Keep DHCP broadcasts inside this Docker bridge. No host networking or published
# ports are needed, and --internal prevents access beyond the test network.
docker network create \
	--driver bridge \
	--internal \
	--subnet "$NETWORK_SUBNET" \
	--ip-range "$NETWORK_IP_RANGE" \
	--gateway 192.0.2.1 \
	--label "${RESOURCE_LABEL}=${RESOURCE_TOKEN}" \
	"$NETWORK_NAME" >/dev/null

# Ask the newly built binary to check the config before starting the real server.
# Only the config mount is read-only; Kea can still write its runtime files.
timeout --signal=TERM --kill-after=5s 30s docker run --rm \
	--network "$NETWORK_NAME" \
	-v "$WORK_DIR:/kea/config:ro" \
	"$SERVER_IMAGE" -t /kea/config/dhcp4.json

docker run --detach \
	--name "$SERVER_NAME" \
	--label "${RESOURCE_LABEL}=${RESOURCE_TOKEN}" \
	--network "$NETWORK_NAME" \
	--ip "$SERVER_IP" \
	-v "$WORK_DIR:/kea/config:ro" \
	"$SERVER_IMAGE" -c /kea/config/dhcp4.json >/dev/null

# Container startup is asynchronous. Wait for Kea's readiness message, not merely
# Docker reporting a running process; fail early if Kea exits during startup.
server_ready=0
for attempt in {1..30}; do
	if ! docker inspect --format '{{.State.Running}}' "$SERVER_NAME" 2>/dev/null | grep -qx true; then
		printf 'Kea container exited before reporting readiness.\n' >&2
		exit 1
	fi
	if docker logs "$SERVER_NAME" 2>&1 | grep -q 'DHCP4_STARTED'; then
		server_ready=1
		break
	fi
	sleep 1
done
if (( server_ready == 0 )); then
	printf 'Kea did not report DHCP4_STARTED within 30 seconds.\n' >&2
	exit 1
fi

# Nmap sends a DHCP DISCOVER with the fixed MAC and listens for broadcast replies.
# Its existing Docker IP is only for container setup, not the offered lease.
# The loopback scan target keeps the ordinary scan local; the NSE pre-scan script
# performs the DHCP exchange on eth0 independently of that target.
docker run --detach \
	--name "$CLIENT_NAME" \
	--label "${RESOURCE_LABEL}=${RESOURCE_TOKEN}" \
	--network "$NETWORK_NAME" \
	--ip "$CLIENT_IP" \
	--cap-add NET_RAW \
	--user 0 \
	"$CLIENT_IMAGE" \
	nmap -e eth0 -sn \
	--script broadcast-dhcp-discover \
	--script-args "broadcast-dhcp-discover.mac=${CLIENT_MAC},broadcast-dhcp-discover.timeout=${OFFER_TIMEOUT}" \
	127.0.0.1 >/dev/null

# Bound the whole client run as well as its DHCP listener. docker wait returns
# the container exit status as output; its own exit code only describes the wait.
if ! timeout --signal=TERM --kill-after=5s 30s docker wait "$CLIENT_NAME" > "$WORK_DIR/client-exit-code"; then
	printf 'DHCP client did not finish within 30 seconds.\n' >&2
	exit 1
fi
client_exit_code="$(<"$WORK_DIR/client-exit-code")"
if [[ "$client_exit_code" != 0 ]]; then
	printf 'DHCP client exited with status %s.\n' "$client_exit_code" >&2
	exit 1
fi
docker logs "$CLIENT_NAME" > "$WORK_DIR/client-output" 2>&1

# Require an actual received OFFER, the expected server identity, and an address
# in the configured pool. Do not assume Kea will always choose its first address.
if ! response="$(parse_client_response "$WORK_DIR/client-output")"; then
	printf 'Expected exactly one complete DHCP offer in the client output.\n' >&2
	exit 1
fi
IFS=$'\t' read -r response_interface offered_ip message_type server_identifier <<< "$response"
if [[ "$response_interface" != eth0 || "$message_type" != DHCPOFFER || "$server_identifier" != "$SERVER_IP" || ! "$offered_ip" =~ ^192\.0\.2\.(1[0-9]|20)$ ]]; then
	printf 'Unexpected DHCP response: interface=%s offered_ip=%s type=%s server_id=%s\n' \
		"$response_interface" "$offered_ip" "$message_type" "$server_identifier" >&2
	exit 1
fi

# A send-attempt log does not prove delivery: Nmap's response proves that above.
# Now require the matching lease and transaction in Kea's logs. Allow a short
# delay for Docker to expose all log lines before declaring a mismatch.
logs_verified=0
for attempt in {1..5}; do
	docker logs "$SERVER_NAME" > "$WORK_DIR/server-output" 2>&1
	if verify_server_logs "$WORK_DIR/server-output" "$offered_ip"; then
		logs_verified=1
		break
	fi
	sleep 1
done
if (( logs_verified == 0 )); then
	printf 'Kea logs did not contain matching DISCOVER, lease-offer, and OFFER-send events.\n' >&2
	exit 1
fi

printf 'DHCPv4 offer verified: image=%s client=%s offered_ip=%s server_id=%s\n' \
	"$SERVER_IMAGE" "$CLIENT_MAC" "$offered_ip" "$server_identifier"
