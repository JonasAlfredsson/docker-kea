# Verify the Kea events for one DHCPv4 offer received by the test client.
# Supply mac, offered_ip, and server_ip with awk -v; read docker logs as input.
# Exit zero only when the matching DISCOVER, lease offer, and OFFER send exist.
BEGIN { mac = tolower(mac) }
{
	line = tolower($0)

	# Ignore other clients. Kea formats this identity as [hwtype=1 <MAC>].
	if (!index(line, " " mac "]")) next
	if (!match(line, /tid=0x[[:xdigit:]]+/)) next
	transaction = substr(line, RSTART, RLENGTH)

	# Count events by transaction, not just MAC: unrelated exchanges from the
	# same client must not supply a missing DISCOVER or OFFER-send event.
	if (index(line, "dhcp4_packet_received ") &&
	    index(line, "dhcpdiscover (type 1)")) received[transaction]++

	if (index(line, "dhcp4_lease_offer ") &&
	    index(line, "lease " offered_ip " will be offered")) {
		offer_transaction = transaction
		offers++
	}

	# The destination can be broadcast; the lease address is checked above.
	if (index(line, "dhcp4_packet_send ") &&
	    index(line, "dhcpoffer (type 2)") &&
	    index(line, "from " server_ip ":67 ") &&
	    line ~ /to [0-9.]+:68 /) sent[transaction]++

	if (index(line, "dhcp4_packet_send_fail ")) failed[transaction]++
}
END {
	if (offers != 1 || received[offer_transaction] != 1 ||
	    sent[offer_transaction] != 1 || failed[offer_transaction] != 0) exit 1
}
