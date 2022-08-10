# The Makefile will be the "source of truth" when it comes to which version of
# Kea we are to build. Having it in a single place will make life easier for us
# in the future.
KEA_VERSION="2.1.7"

# These are the build functions, they will in turn call upon the Bash script
# with the correct arguments.
.PHONY: all
all: dhcp4 dhcp6 ctrl-agent

.PHONY: all-alpine
all-alpine: dhcp4-alpine dhcp6-alpine ctrl-agent-alpine

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

.PHONY: release
release:
	./build_release.sh $(KEA_VERSION)

# After the dhcp4 target has been executed it is possible to call on this one
# to start the local build. It has a super simple config which will most likely
# work on the default docker bridge network, else you need to tune it.
.PHONY: run4
run4:
	docker run -it --rm \
		-v $(PWD)/examples/simple:/kea/config \
		kea-dhcp4:local \
		-c /kea/config/dhcp4.json

.PHONY: run4-alpine
run4-alpine:
	docker run -it --rm \
		-v $(PWD)/examples/simple:/kea/config \
		kea-dhcp4:local-alpine \
		-c /kea/config/dhcp4.json

# If you have managed to start the run4 target you may see if the DHCP server
# responds by calling this. It should print a detailed response and the logs
# in Kea should move if done correctly.
.PHONY: test4
test4:
	docker run -it --rm \
		jonasal/network-tools:latest \
		nmap --script broadcast-dhcp-discover
