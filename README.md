# docker-kea

The ISC (Internet System Consortium) Kea DHCP server running inside a Docker
container. Separate images for the IPv4 and IPv6 services, as well as an image
for the Control Agent which exposes a RESTful API that can be used for
querying/controlling the other services.

Available as both Debian and Alpine images and for multiple architectures. In
order to facilitate the last part this repo needs to build Kea from source,
so it might not be 100% identical to the official ISC package.

---

[Kea][1] is the successor of the old [ISC DHCP][2] server which will reach
its end of life sometime during 2022, so it is recommended to start
[migrating][5] now. It is built with the modern web in mind, and is more modular
with separate [packages][3] for the different services along with a lot of
[documentation][4].

To keep the same modularity in the Docker case this repo produces three
different images which are tagged with the same version as the Kea service
running inside:

- [`jonasal/kea-dhcp4:<version>`][12]
- [`jonasal/kea-dhcp6:<version>`][13]
- [`jonasal/kea-ctrl-agent:<version>`][14]

> Just append `-alpine` to the tags above to get the Alpine image.

It is possible to define how strict you want to lock down the version so `2`,
`2.1` or `2.1.7` all work and the less specific tags will move to point to the
latest of the more specific ones.

> There is no [`:latest`][15] tag since Kea updates may break things.

## Usage

### Environment Variables

- `KEA_EXECUTABLE`: Should **not** be modified, is used by [`entrypoint.sh`](./entrypoint.sh).
- `KEA_USER`: Currently does nothing, might be used in the future.

### Useful Directories
There are a few directories present inside the images that may be utilized if
your usecase calls for it.

> This image creates the user `kea` with uid:gid `101:101`/`100:101`
> (Debian/Alpine) which may be used for non-root execution in the future,
> however, Kea runs as root right now since it needs high privilege to open
> raw sockets.

- `/kea/config`: Mount this to the directory with all your configuration files.
- `/kea/leases`: Good location to place the leases memfile if used.
- `/kea/logs`: Good location to output any logs to.
- `/kea/sockets`: Host mount this in order to share sockets between containers.
- `/entrypoint.d`: Place any custom scripts you want executed at the start of the container here.

All the folders under `kea/` may be mounted individually or you can just mount
the entire `kea/` folder, however, then you need to manually create the
subfolders since Kea is not able to do so itself. See the advanced
[docker-compose](./examples/docker-compose.yaml) example for inspiration.

### The DHCP Server
Each image/service needs its own specific configuration file, so you will need
to create one for each service you want to run. There is a very simple config
for the `dhcp4` service in the [simple/](./examples/simple/dhcp4.json) folder,
with more comprehensive ones for all services in the
[advanced/](./examples/advanced/) folder. You may then also look at the
[official repository][6] for some [more settings][7] or go to the
[documentation][4] for the latest info.

> The syntax used is extended JSON with another couple of addons which allows
> comments and file inclusion. This is very handy and makes it much easier to
> write well structured configuration files.

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
When you want to run your DHCP server for real you will need to set the
container to use the `host` network, else the requests and responses will not
leave the Docker network. You *could* [fiddle][9] with a [macvlan][8] setup,
but I would not bother. Furthermore, [IPv6 support][10] in Docker is a little
bit [messy][11] right now so with that one your other choices are a bit limited
either way.

Setting the `host` network is done by adding

```bash
--network host
```

to the command above, or look at the [docker-compose](./examples/docker-compose.yaml)
file for how it is done there. Then you should be able to serve leases on the
network the host machine is connected to.


### The Control Agent
The DHCP services expose an API that may be used if the `control-socket`
setting is defined in their configuration file:

```json
"control-socket": {
    "socket-type": "unix",
    "socket-name": "/kea/socket/dhcp4.socket"
},
```

A unix socket is the only method available, and while you can push commands
directly through this with the help of `socat` the `ctrl-agent` service
provides a RESTful API that may be interfaced with instead. You just need
to make sure this service can communicate with the `control-socket` of the DHCP
service, and an example of how to do this can be found in the
[advanced/](./examples/advanced/) folder along with the
[docker-compose.yaml](./examples/docker-compose.yaml) file.

When that is all up and running you should be able to make queries like this:

```bash
curl -X POST -H "Content-Type: application/json" \
    -d '{ "command": "config-get", "service": [ "dhcp4" ] }' \
    http://localhost:8000/
```

More information about this may be found in the Management API section of the
[documentation][4].






[1]: https://www.isc.org/kea/
[2]: https://www.isc.org/dhcp/
[3]: https://kb.isc.org/docs/isc-kea-packages
[4]: https://kea.readthedocs.io
[5]: https://academy.apnic.net/wp-content/uploads/2020/03/kea-apnic-webinar.pdf
[6]: https://github.com/isc-projects/kea/tree/master/src/bin/keactrl
[7]: https://fossies.org/linux/kea/doc/examples/kea4/all-keys.json
[8]: https://docs.docker.com/network/macvlan/
[9]: https://gist.github.com/mikejoh/04978da4d52447ead7bdd045e878587d
[10]: https://docs.docker.com/config/daemon/ipv6/
[11]: https://github.com/robbertkl/docker-ipv6nat
[12]: https://hub.docker.com/r/jonasal/kea-dhcp4/tags
[13]: https://hub.docker.com/r/jonasal/kea-dhcp6/tags
[14]: https://hub.docker.com/r/jonasal/kea-ctrl-agent/tags
[15]: https://vsupalov.com/docker-latest-tag/
