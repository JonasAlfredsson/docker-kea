# docker-kea

The ISC (Internet System Consortium) Kea DHCP server running inside a Docker
container. Separate images for the IPv4 and IPv6 services, as well as an image
for the Control Agent which exposes a RESTful API that can be used for
querying/controlling the other services.

Available as both Debian and Alpine images and for multiple architectures. In
order to facilitate the last part this repo needs to build Kea from source,
so it might not be 100% identical to the official ISC package, which is
unfortunate but it will probably have to remain like this until official
packages are built for all architectures.

> There is also an [Ansible role][19] using this image, if that is of interest.

---

[Kea][1] is the successor of the old [ISC DHCP][2] server which reached its end
of life [late 2022][28], so it is recommended to [migrate][29] to Kea now if you
are still using the old service. Kea is built with the modern web in mind
([intro presentation][5]), and is more modular with separate [packages][3] for
the different services along with a lot of [documentation][4].

To keep the same modularity in the Docker case this repo produces four
different images which are tagged with the same version as the Kea service
running inside:

- [`jonasal/kea-dhcp4:<version>`][12]
- [`jonasal/kea-dhcp6:<version>`][13]
- [`jonasal/kea-dhcp-ddns:<version>`][25]
- [`jonasal/kea-ctrl-agent:<version>`][14]
- (+ [`jonasal/kea-hooks:<version>`][16] - read about this in the [Kea Hooks](#kea-hooks) section)

> Just append `-alpine` to the tags above to get the Alpine image.

It is possible to define how strict you want to lock down the version so `2`,
`2.2` or `2.2.0` all work and the less specific tags will move to point to the
latest of the more specific ones. One thing to be aware of is that **even**
minor versions (`2.2`) are stable builds while **odd** (`2.3`) are development
builds, therefore the major tagging of all the images built here will only track
the stable releases. What this means is that `2 -> 2.2.0` even though `2.3.1` is
available.

> There is no [`:latest`][15] tag since Kea updates may break things.

## Usage

### Environment Variables
There are a couple of environment variables present in the container that
allow for some customization, however, some of them should not be touched.

#### Executable Information
- `KEA_EXECUTABLE`: Should **not** be modified, is used by [`entrypoint.sh`](./entrypoint.sh).
- `KEA_USER`: Currently does nothing, might be used in the future.

#### Data Directories
Because of strict [path limitations][31] these variables need to be defined in
order to allow us to use the directory structure mentioned
[below](#useful-directories). These can be changed if desired.

- `KEA_DHCP_DATA_DIR`: Location of the leases "memfile" (Default: `/kea/leases`)
- `KEA_LOG_FILE_DIR`: Output directory of log files (Default: `/kea/logs`)
- `KEA_LEGAL_LOG_DIR`: Output directory of forensic log files (Default: `/kea/logs`)
- `KEA_CONTROL_SOCKET_DIR`: Directory for any sockets created (Default: `/kea/sockets`)

### Useful Directories
There are a few directories present inside the images that may be utilized if
your usecase calls for it.

> This image creates the user `kea` with uid:gid `101:101`/`100:101`
> (Debian/Alpine) which may be used for non-root execution in the future,
> however, Kea runs as root right now since it needs high privilege to open
> raw sockets.

- `/kea/config`: Mount this to the directory with all your configuration files.
- `/kea/leases`: Good location for the leases "memfile" if used.
- `/kea/logs`: Good location to output any logs to.
- `/kea/sockets`: Host mount this in order to share sockets between containers.
- `/entrypoint.d`: Place any custom scripts you want executed at the start of the container here.

All the folders under `kea/` may be mounted individually or you can just mount
the entire `kea/` folder, however, then you need to manually create the
subfolders (with `750` permissions) since Kea is not able to do so itself. See
the advanced [docker-compose](./examples/advanced/docker-compose.yaml) example
for inspiration.

### The DHCP Server
Each image/service needs its own specific configuration file, so you will need
to create one for each service you want to run. There is a very simple config
for the `dhcp4` service in the [simple/](./examples/simple/dhcp4.json) folder,
with more comprehensive ones for all services in the
[advanced/](./examples/advanced/) folder. You may also look in the [examples][6]
folder on the official repo to find stuff like [all available keys][7] for the
DHCP4 config, or go to the [documentation][20] for the latest info.

> The syntax used is [extended JSON with another couple of addons][21] which
> allows comments and file inclusion. This is very handy and makes it much
> easier to write well structured configuration files.

When starting the service you need to make sure that you point it to the correct
configuration file. In the simple example we would provide the following command
to have it find the correct file:

```bash
docker run -it --rm \
    -v $(pwd)/examples/simple:/kea/config \
    jonasal/kea-dhcp4:2 \
    -c /kea/config/dhcp4.json
```

This container will run inside a Docker network so it should not interfere with
anything. You can test to see if it responds correctly by calling upon the
`test4` target from the [Makefile](./Makefile).

```bash
make test4
```

To start the IPv6 service you just replace all instances of `dhcp4` with `dhcp6`
in the command above. However, I would suggest you read the
[next section](#docker-network-mode) about the Docker network mode and how that
affects these services before trying anything else.

#### Docker Network Mode
When you want to run your DHCP server for real you will need to make sure that
the incoming [DHCP packages][22] can reach your service, and this will not
happen in case you put the containers on a normal Docker network.

For basic home use I would recommend just setting the container to use the
[`host`][24] network, since this will be the absolute easiest way to get around
most issues.  However, you *could* [fiddle][9] with a [macvlan][8] or an
[ipvlan][23] ([example](./examples/multiple-vlans/docker-compose.yml)) setup in
case you have more advanced needs, but unless you know you need this I would not
bother.

Additionally, [IPv6 support][10] in Docker is a little bit [messy][11] right
now so if you want to deploy that your other choices are a bit limited either
way.

Setting the `host` network is done by adding

```bash
--network host
```

to the command above, or look at the
[docker-compose](./examples/advanced/docker-compose.yaml)
file for how it is done there. Then you should be able to serve leases on the
network the host machine is connected to.


### The Control Agent
The DHCP services expose an API that may be used if the `control-socket`
setting is defined in their configuration file:

```json
"control-socket": {
    "socket-type": "unix",
    "socket-name": "/kea/sockets/dhcp4.socket"
},
```

A unix socket is the only method available, and while you can push commands
directly through this with the help of [`socat`][30] the `ctrl-agent` service
provides a RESTful API that may be interfaced with instead. You just need
to make sure this service can communicate with the `control-socket` of the DHCP
service, and an example of how to do this can be found in the
[advanced/](./examples/advanced/) folder along with the
[docker-compose.yaml](./examples/advanced/docker-compose.yaml) file.

When that is all up and running you should be able to make queries like this:

```bash
curl -X POST -H "Content-Type: application/json" \
    -d '{ "command": "config-get", "service": [ "dhcp4" ] }' \
    http://localhost:8000/
```

More information about this may be found in the Management API section of the
[documentation][4].



### Kea Hooks
Kea has some extended features that are available as "[hooks][17]" which may be
imported in those cases when they are specifically needed. Some are available
as free open source while others require a premium subscription in order to get
them, a table exists [here][18] with more info.

These hooks enable advanced functionality, like High Availability and BOOTP,
which means most people will probably never use these, and which is why we
provide `dhcp4-slim` and `dhcp6-slim` images which don't have any hook libraries
included at all.

However, if you want to make your own specialized image we do provide an
additional image from where individual hooks may be imported. In the example
below we just import the HA hooks into the `dhcp4-slim` service image.

```Dockerfile
FROM jonasal/kea-dhcp4-slim:2.2.0
COPY --from=jonasal/kea-hooks:2.2.0 /hooks/libdhcp_ha.so /hooks/libdhcp_lease_cmds.so /usr/local/lib/kea/hooks
```

It could also be necessary to run the linker after this, so just to be safe I
would add one of the following lines afterwards.

```Dockerfile
RUN ldconfig  # <--- Debian
or
RUN ldconfig /usr/local/lib/kea/hooks  # <--- Alpine
```






[1]: https://www.isc.org/kea/
[2]: https://www.isc.org/dhcp/
[3]: https://kb.isc.org/docs/isc-kea-packages
[4]: https://kea.readthedocs.io
[5]: https://academy.apnic.net/wp-content/uploads/2020/03/kea-apnic-webinar.pdf
[6]: https://github.com/isc-projects/kea/tree/master/doc/examples
[7]: https://github.com/isc-projects/kea/blob/master/doc/examples/kea4/all-keys.json
[8]: https://docs.docker.com/network/macvlan/
[9]: https://gist.github.com/mikejoh/04978da4d52447ead7bdd045e878587d
[10]: https://docs.docker.com/config/daemon/ipv6/
[11]: https://github.com/robbertkl/docker-ipv6nat
[12]: https://hub.docker.com/r/jonasal/kea-dhcp4/tags
[13]: https://hub.docker.com/r/jonasal/kea-dhcp6/tags
[14]: https://hub.docker.com/r/jonasal/kea-ctrl-agent/tags
[15]: https://vsupalov.com/docker-latest-tag/
[16]: https://hub.docker.com/r/jonasal/kea-hooks/tags
[17]: https://kea.readthedocs.io/en/latest/arm/hooks.html
[18]: https://kea.readthedocs.io/en/latest/arm/hooks.html#id1
[19]: https://github.com/JonasAlfredsson/ansible-role-kea_dhcp
[20]: https://kea.readthedocs.io/en/latest/arm/config.html
[21]: https://kea.readthedocs.io/en/latest/arm/config.html#json-syntax
[22]: https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol#DHCP_message_types
[23]: https://docs.docker.com/network/ipvlan/
[24]: https://docs.docker.com/network/host/
[25]: https://hub.docker.com/r/jonasal/kea-dhcp-ddns/tags
[28]: https://www.isc.org/blogs/isc-dhcp-eol/
[29]: https://www.isc.org/dhcp_migration/
[30]: https://reports.kea.isc.org/dev_guide/d2/d96/ctrlSocket.html#ctrlSocketClient
[31]: https://github.com/JonasAlfredsson/docker-kea/issues/82
