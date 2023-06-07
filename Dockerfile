#
# Define the base OS image in a single place.
#
FROM debian:bullseye-slim AS base

#
# The builder step is where Kea is compiled.
#
FROM base AS builder
ARG DEBIAN_FRONTEND=noninteractive

# Install all packages needed to build Kea.
RUN apt-get update && apt-get install -y \
        apt-transport-https \
        gnupg2 \
    && apt-get install -y \
        build-essential \
        curl \
        libboost-system-dev \
        libkrb5-dev \
        liblog4cplus-dev \
        libmariadb-dev \
        libmariadb-dev-compat \
        libssl-dev=1.1.1* \
        postgresql-server-dev-all

ARG KEA_VERSION
# Download and unpack the correct tarball (also verify the signature).
RUN curl -LOR "https://ftp.isc.org/isc/kea/${KEA_VERSION}/kea-${KEA_VERSION}.tar.gz{,.asc}" && \
    install -m 0700 -o root -g root -d /root/.gnupg && \
    curl -L "https://www.isc.org/docs/isc-keyblock.asc" | gpg2 --import && \
    gpg2 --no-options --verbose --keyid-format 0xlong --keyserver-options auto-key-retrieve=true \
        --verify kea-${KEA_VERSION}.tar.gz.asc kea-${KEA_VERSION}.tar.gz && \
    tar xzpf kea-${KEA_VERSION}.tar.gz

# Set the extracted location as our new workdir.
WORKDIR /kea-${KEA_VERSION}

# Configure with all the settings we want, and then build it.
# This will take ~5 hours for arm/v7 on an average 4 core desktop.
RUN ./configure --with-openssl --with-mysql --with-pgsql --with-gssapi --enable-static=no && \
    make -j$(nproc)

# Having this in its own step makes it easier to experiment.
RUN make install

# Let's reduce the files needed to be copied later by removing stuff we don't
# seem to need.
RUN cd /usr/local/lib/ && \
    rm -v *.la && \
    rm -v kea/hooks/*.la

# Strip debug symbols to reduce file size of binaries
RUN find /usr/local/sbin/ /usr/local/lib/ -type f -exec strip --strip-unneeded {} \;

# There are a couple additional "hook" features located in this folder which
# will most likely not be needed by the average user, so let's exclude them
# from the COPY step later.
RUN mv "/usr/local/lib/kea/hooks" / && mkdir "/usr/local/lib/kea/hooks"



#
# All the services basically need the same stuff so let's make a common layer.
#
FROM base AS common
ARG DEBIAN_FRONTEND=noninteractive

# In Debian the APT package installs the user "_kea", with uid 101 and gid 101,
# but the leading underscore in the name would require us to add the
# "--force-badname" flag which seems suboptimal. I have therefore made the
# decision to use the name without this underscore.
# Currently this does not make Kea run as this user, but we prepare for it.
ENV KEA_USER=kea
RUN addgroup --system --gid 101 ${KEA_USER} && \
    adduser --system --disabled-login --ingroup ${KEA_USER} --no-create-home --gecos "Kea user" --shell /bin/false --uid 101 ${KEA_USER} && \
# We then need to install all the runtime dependencies of Kea.
# This is not identical to what is pulled in when doing an apt-get install of
# the official package, but it appears to work fine.
    apt-get update && apt-get install -y \
        libboost-system1.74.0 \
        libkrb5-3 \
        liblog4cplus-2.0.5 \
        libmariadb3 \
        libpq5 \
        libssl1.1 \
    && \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/* \
    && \
# Make sure some directories mentioned in the documentation are present and
# owned by the Kea user.
    install -m 0775 -o ${KEA_USER} -g ${KEA_USER} -d \
        /opt/kea \
        /usr/local/var/log/kea \
        /usr/local/var/lib/kea \
        /usr/local/var/run/kea \
    && \
# Create directories we want available for easy configuration management.
    install -m 0775 -o ${KEA_USER} -g ${KEA_USER} -d \
          /kea \
          /kea/config \
          /kea/leases \
          /kea/logs \
          /kea/sockets \
    && \
    mkdir /entrypoint.d

# From the build stage we copy the library files from "lib", and then all the
# C++ header files in the "include" folder. There are a couple of folders used
# during runtime in "var" as well, but we created them above with the Kea user
# as the owner instead.
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/include/kea /usr/local/include/kea

# As a final step we will need to run ldconfig to make sure that all the Kea
# libraries that we copied are correctly linked. This is an extra config
# file which adds a folder to the standard search locations.
#
# NOTE: The hooks folder is empty right now, to save some space, but it may be
#       populated by the user later.
RUN echo "/usr/local/lib/kea/hooks" > /etc/ld.so.conf.d/kea.conf && \
    ldconfig

# Finally we copy the common entrypoint script which will read an environment
# variable in order to later launch the correct service.
COPY entrypoint.sh /
ENTRYPOINT [ "/entrypoint.sh" ]




#
# The DHCP4 service image.
#
FROM common AS dhcp4-target
ENV KEA_EXECUTABLE=dhcp4
COPY --from=builder /usr/local/sbin/kea-dhcp4 /usr/local/sbin/kea-lfc /usr/local/sbin/

#
# The DHCP4 service image with high-availability hooks included.
#
FROM dhcp4-target AS dhcp4-ha-target
COPY --from=builder /hooks/libdhcp_ha.so /hooks/libdhcp_lease_cmds.so /usr/local/lib/kea/hooks/


#
# The DHCP6 service image.
#
FROM common AS dhcp6-target
ENV KEA_EXECUTABLE=dhcp6
COPY --from=builder /usr/local/sbin/kea-dhcp6 /usr/local/sbin/kea-lfc /usr/local/sbin/

#
# The DHCP6 service image with high-availability hooks included.
#
FROM dhcp6-target AS dhcp6-ha-target
COPY --from=builder /hooks/libdhcp_ha.so /hooks/libdhcp_lease_cmds.so /usr/local/lib/kea/hooks/


#
# The Kea Control Agent service image.
#
FROM common AS ctrl-agent-target
ENV KEA_EXECUTABLE=ctrl-agent
COPY --from=builder /usr/local/sbin/kea-ctrl-agent /usr/local/sbin/


#
# The Kea DHCP DDNS service image.
#
FROM common AS dhcp-ddns-target
ENV KEA_EXECUTABLE=dhcp-ddns
COPY --from=builder /usr/local/sbin/kea-dhcp-ddns /usr/local/sbin/


#
# The Hooks image.
#
FROM base AS hooks-target
COPY --from=builder /hooks /hooks
CMD [ "ls", "-ahl", "/hooks" ]
