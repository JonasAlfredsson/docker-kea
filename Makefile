# The Makefile will be the "source of truth" when it comes to which version of
# Kea we are to build. Having it in a single place will make life easier for us
# in the future.
KEA_VERSION="2.1.7"

# These are the build functions, they will in turn call upon the Bash script
# with the correct arguments.
.PHONY: dhcp4
dhcp4:
	./build.sh "dhcp4" $(KEA_VERSION)

.PHONY: dhcp4-alpine
dhcp4-alpine:
	./build.sh "dhcp4" $(KEA_VERSION) "alpine"

.PHONY: dhcp6
dhcp6:
	./build.sh "dhcp6" $(KEA_VERSION)

.PHONY: dhcp6-alpine
dhcp6-alpine:
	./build.sh "dhcp6" $(KEA_VERSION) "alpine"

.PHONY: ctrl-agent
ctrl-agent:
	./build.sh "ctrl-agent" $(KEA_VERSION)

.PHONY: ctrl-agent-alpine
ctrl-agent-alpine:
	./build.sh "ctrl-agent" $(KEA_VERSION) "alpine"
