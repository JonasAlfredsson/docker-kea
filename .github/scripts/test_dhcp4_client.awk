# Convert one Nmap DHCP offer into tab-separated interface, IP, type, and server.
# Read client output as input; reject missing fields, duplicates, or multiple offers.

# Capture a named Nmap result field and count duplicates.
function capture(field) {
	if (index(line, field ":") == 1) {
		counts[field]++
		value = line
		sub("^[^:]+:[[:space:]]*", "", value)
		values[field] = value
	}
}
{
	# Nmap prefixes script output with | or |_; neither is response data.
	line = $0
	sub(/^\|_?[[:space:]]*/, "", line)
	if (line ~ /^Response [0-9]+ of [0-9]+:/) responses++
	capture("Interface")
	capture("IP Offered")
	capture("DHCP Message Type")
	capture("Server Identifier")
}
END {
	# Empty output and multiple offers are failures, even if Nmap exits zero.
	if (responses != 1 || counts["Interface"] != 1 ||
	    counts["IP Offered"] != 1 || counts["DHCP Message Type"] != 1 ||
	    counts["Server Identifier"] != 1) exit 1
	printf "%s\t%s\t%s\t%s\n", values["Interface"], values["IP Offered"],
	       values["DHCP Message Type"], values["Server Identifier"]
}
