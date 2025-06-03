#
# Define the base OS image in a single place.
#
FROM debian:bookworm-slim AS base

#
# The builder step is where Kea is compiled.
#
FROM base AS builder
ARG DEBIAN_FRONTEND=noninteractive

# Install all packages needed to build Kea.
RUN apt-get update
ARG PG_INSTALL_VERSION=15
RUN apt-get install -qq -y \
        apt-transport-https \
        gnupg2 \
    && apt-get install -qq -y \
        build-essential \
        curl \
        libboost-system-dev \
        libkrb5-dev \
        liblog4cplus-dev \
        liblz4-dev \
        libmariadb-dev \
        libmariadb-dev-compat \
        libpam-dev \
        libreadline-dev \
        libselinux1-dev \
        libssl-dev=3.0.* \
        libxslt1-dev \
        libzstd-dev \
        postgresql-server-dev-${PG_INSTALL_VERSION} \
    && \
# The PostgreSQL libs are at /usr/lib/postgresql/{version}/lib, symlink them to
# a location which will be included automatically during the compile step.
    ln -snf /usr/lib/postgresql/${PG_INSTALL_VERSION}/lib/*.a /usr/local/lib/

# Needed in order to install Python packages via PIP after PEP 668 was
# introduced, but I believe this is safe since we are in a container without
# any real need to cater to other programs/environments.
ARG PIP_BREAK_SYSTEM_PACKAGES=1

# Install Python and then meson from pip to get up to date release.
RUN apt-get install -qq -y \
        python3 \
    && \
# Install the latest version of PIP, Setuptools and Wheel.
    curl -L 'https://bootstrap.pypa.io/get-pip.py' | python3 && \
# Install the necessary pip packages.
    pip install meson ninja

# Assert that the PGP Public key is the same as the one in this repo, and then
# install it for the verification step.
COPY isc-keyblock.asc /
RUN curl -L "https://www.isc.org/docs/isc-keyblock.asc" -o /latest_key.isc && \
    diff /isc-keyblock.asc /latest_key.isc && \
    install -m 0700 -o root -g root -d /root/.gnupg && \
    gpg2 --import /isc-keyblock.asc

ARG KEA_VERSION
# Download and unpack the correct tarball (also verify the signature).
RUN curl -LORf "https://ftp.isc.org/isc/kea/${KEA_VERSION}/kea-${KEA_VERSION}.tar.xz{,.asc}" && \
    gpg2 --no-options --verbose --keyid-format 0xlong --keyserver-options auto-key-retrieve=true \
        --verify kea-${KEA_VERSION}.tar.xz.asc kea-${KEA_VERSION}.tar.xz && \
    tar xpf kea-${KEA_VERSION}.tar.xz

# Set the extracted location as our new workdir.
WORKDIR /kea-${KEA_VERSION}

# Configure with all the settings we want.
RUN meson setup build \
    --buildtype release \
    --install-umask 0027 \
    --strip \
    --prefix /usr/local \
    --libdir /usr/local/lib \
    -D mysql=enabled \
    -D postgresql=enabled \
    -D krb5=enabled \
    -D crypto=openssl \
    -D netconf=disabled \
    -D cpp_std=c++20

# Then we build and install Kea. Having these as individual steps makes it
# easier to experiment.
# NOTE: This will take ~5 hours for arm/v7 on an average 4 core desktop.
RUN meson compile -C build
RUN meson install -C build

# There are a couple additional "hook" features located in this folder which
# will most likely not be needed by the average user, so let's exclude them
# from the first COPY step later so we can make a "slim" image.
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
ENV KEA_USER=kea \
# Since 2.7.9/2.6.3/2.4.2 we need to define these variables, else Kea will not
# start: https://github.com/JonasAlfredsson/docker-kea/issues/82
    KEA_DHCP_DATA_DIR=/kea/leases \
    KEA_LOG_FILE_DIR=/kea/logs \
    KEA_LEGAL_LOG_DIR=/kea/logs \
    KEA_CONTROL_SOCKET_DIR=/kea/sockets

RUN addgroup --system --gid 101 ${KEA_USER} && \
    adduser --system --disabled-login --ingroup ${KEA_USER} --no-create-home --gecos "Kea user" --shell /bin/false --uid 101 ${KEA_USER} && \
# We then need to install all the runtime dependencies of Kea.
# This is not identical to what is pulled in when doing an apt-get install of
# the official package, but it appears to work fine.
    apt-get update && apt-get install -y \
        libboost-system1.81.0 \
        libkrb5-3 \
        liblog4cplus-2.0.5 \
        libmariadb3 \
        libpq5 \
        libssl3 \
    && \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/* \
    && \
# Make sure some directories mentioned in the documentation are present and
# owned by the Kea user.
    install -m 0750 -o ${KEA_USER} -g ${KEA_USER} -d \
        /opt/kea \
        /usr/local/var/log/kea \
        /usr/local/var/lib/kea \
        /usr/local/var/run/kea \
    && \
# Create directories we want available for easy configuration management.
    install -m 0750 -o ${KEA_USER} -g ${KEA_USER} -d \
          /kea \
          /kea/config \
          ${KEA_DHCP_DATA_DIR} \
          ${KEA_LOG_FILE_DIR} \
          ${KEA_LEGAL_LOG_DIR} \
          ${KEA_CONTROL_SOCKET_DIR} \
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
# The DHCP4 service image without any hook libraries.
#
FROM common AS dhcp4-slim
ENV KEA_EXECUTABLE=dhcp4
COPY --from=builder /usr/local/sbin/kea-dhcp4 /usr/local/sbin/kea-lfc /usr/local/sbin/

#
# The DHCP4 service image with all relevant hooks included.
#
FROM dhcp4-slim AS dhcp4
COPY --from=builder /hooks/* /usr/local/lib/kea/hooks/


#
# The DHCP6 service image without any hook libraries.
#
FROM common AS dhcp6-slim
ENV KEA_EXECUTABLE=dhcp6
COPY --from=builder /usr/local/sbin/kea-dhcp6 /usr/local/sbin/kea-lfc /usr/local/sbin/

#
# The DHCP6 service image with all relevant hooks included.
#
FROM dhcp6-slim AS dhcp6
COPY --from=builder /hooks/* /usr/local/lib/kea/hooks/


#
# The Kea Control Agent service image.
#
FROM common AS ctrl-agent
ENV KEA_EXECUTABLE=ctrl-agent
COPY --from=builder /usr/local/sbin/kea-ctrl-agent /usr/local/sbin/


#
# The Kea DHCP DDNS service image.
#
FROM common AS dhcp-ddns
ENV KEA_EXECUTABLE=dhcp-ddns
COPY --from=builder /usr/local/sbin/kea-dhcp-ddns /usr/local/sbin/


#
# The Hooks image.
#
FROM base AS hooks
COPY --from=builder /hooks /hooks
CMD [ "ls", "-ahl", "/hooks" ]
