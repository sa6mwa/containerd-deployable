# containerd

Installation of rootless `containerd` from source.

## Repositories

* <https://github.com/containerd/containerd>
* <https://github.com/opencontainers/runc>
* <https://github.com/containerd/nerdctl>
* <https://github.com/containernetworking/plugins>
* <https://github.com/moby/buildkit>
* <https://github.com/rootless-containers/rootlesskit>
* <https://github.com/rootless-containers/slirp4netns>

## Basic prerequisites

You need `gcc` and the usual build tools for your distribution. For a
Debian-based system, the following should suffice...

```console
$ sudo apt-get install build-essential autoconf uidmap
```

**Nota bene**: `newuidmap` is required by `rootlesskit` and can be
found in the `uidmap` package on a Debian-based system.

## Install Go

Get the `getgo` installation helper binary from
<https://github.com/sa6mwa/getgo/releases/getgo> or download the
latest tarball from <https://go.dev> and install according to
instructions. If the Go tooling is installed under the default path of
`/usr/local/go/bin` you will need to add that path in your `PATH`
variable, either in `/etc/environment` or your `~/.profile`,
`~/.bashrc`, etc.

By default, newer versions of Go enable C and dynamic linking to
`glibc` per default (unless cross-compiling), meaning the binaries
will not be statically linked by default. In some contexts where Go is
used, many still prefer the statically linked binaries, especially if
you have multiple target environments with different versions of
`libc` and the loader. The C-bindings can be disabled build-time by
setting the environment variable `CGO_ENABLED` to `0`. Instead of
setting this environment variable in your `.profile` or `.bashrc`
file, consider configuring it for the current user with the `go env
-w` command (stored in `.config/go/env`), disable C Go...

```console
$ go env -w CGO_ENABLED=0
```

Also by default, Go will include the full path to the original source
file(s) in a stack trace, meaning it is embedded into the binary. If
you do not want to leak your username and path to your home folder
when you distribute binaries publically, you can also configure the
`GOFLAGS` variable by adding `-trimpath` which will remove everything
up to the module path...

```console
$ go env -w GOFLAGS=-trimpath
```

Installing a debugger is entirely optional, but as `buildkitd` and
`buildctl` are compiled without optimization and inlining, they are
simple to debug. If you are interested in writing software in Go, I
recommend taking a look at `dlv`
([https://github.com/go-delve/delve](Delve)) and `gdlv`
([GUI frontend for Delve](https://github.com/aarzilli/gdlv)), which
you can install using the following commands...

```console
go install github.com/go-delve/delve/cmd/dlv@latest
go install github.com/aarzilli/gdlv@latest

sudo install -t /usr/local/bin/ $HOME/go/bin/dlv $HOME/go/bin/gdlv
```

To debug an executable built with Go (preferrably with
`-gcflags='all=-N -l'`), run `gdlv exec <binary>`, for example...

```console
$ gdlv exec /usr/local/bin/buildctl
```

Press F10 to next-step, F11 to step into, Shift+F11 to step-out. Type
`help` in the command box in the left hand corner, you can restart a
terminated program by issuing `restart`.

## Clone repositories

Clone with `git` option `--depth=1`. Example using the GitHub CLI...

```console
gh repo clone containerd/containerd -- --depth=1
```

Repeat for all repositories above.

## Install runc

`runc` is used by `containerd` to run containers and it can be used as a stand-alone container runtime, but without all the bells and whistles offered by `containerd`. In the checked out folder of `github.com/opencontainers/runc`, run the following...

```console
$ make static
$ sudo make install
```

If you do not want a statically linked `runc`, just run `make` instead
of `make static`. `static` adds build tags `netgo` and `osusergo` with
`-linkmode external` and `-extldflags -static-pie` added to
`-ldflags`.

## Install containerd

The `Makefile` in the `containerd` top folder will build `bin/ctr`,
`bin/containerd`, and `bin/containerd-stress`.

```console
github.com/containerd/containerd $ make
+ bin/ctr
go build  -gcflags=-trimpath=/home/mike/go/src -buildmode=pie  -o bin/ctr -ldflags '-X github.com/containerd/containerd/v2/version.Version=f8b0736 -X github.com/containerd/containerd/v2/version.Revision=f8b07365d260a69f22371964bb23cbcc73e23790 -X github.com/containerd/containerd/v2/version.Package=github.com/containerd/containerd -s -w ' -tags "urfave_cli_no_docs"  ./cmd/ctr
+ bin/containerd
go build  -gcflags=-trimpath=/home/mike/go/src -buildmode=pie  -o bin/containerd -ldflags '-X github.com/containerd/containerd/v2/version.Version=f8b0736 -X github.com/containerd/containerd/v2/version.Revision=f8b07365d260a69f22371964bb23cbcc73e23790 -X github.com/containerd/containerd/v2/version.Package=github.com/containerd/containerd -s -w ' -tags "urfave_cli_no_docs"  ./cmd/containerd
+ bin/containerd-stress
go build  -gcflags=-trimpath=/home/mike/go/src -buildmode=pie  -o bin/containerd-stress -ldflags '-X github.com/containerd/containerd/v2/version.Version=f8b0736 -X github.com/containerd/containerd/v2/version.Revision=f8b07365d260a69f22371964bb23cbcc73e23790 -X github.com/containerd/containerd/v2/version.Package=github.com/containerd/containerd -s -w ' -tags "urfave_cli_no_docs"  ./cmd/containerd-stress
+ bin/containerd-shim-runc-v2
+ binaries
```

```console
$ sudo make install
[sudo] password for ...: 
+ install bin/ctr bin/containerd bin/containerd-stress bin/containerd-shim-runc-v2
```

## Install common CNI plugins

In the folder you cloned `github.com/containernetworking/plugins`, run
`build_linux.sh`...

```console
$ GOFLAGS=-trimpath ./build_linux.sh
```

This will build a bunch of CNI plugins...

```console
$ ldd bin/*
bin/bandwidth:
        not a dynamic executable
bin/bridge:
        not a dynamic executable
bin/dhcp:
        not a dynamic executable
bin/dummy:
        not a dynamic executable
bin/firewall:
        not a dynamic executable
bin/host-device:
        not a dynamic executable
bin/host-local:
        not a dynamic executable
bin/ipvlan:
        not a dynamic executable
bin/loopback:
        not a dynamic executable
bin/macvlan:
        not a dynamic executable
bin/portmap:
        not a dynamic executable
bin/ptp:
        not a dynamic executable
bin/sbr:
        not a dynamic executable
bin/static:
        not a dynamic executable
bin/tap:
        not a dynamic executable
bin/tuning:
        not a dynamic executable
bin/vlan:
        not a dynamic executable
bin/vrf:
        not a dynamic executable
```

Install all of them under `/opt/cni/bin` (the default used by `nerdctl`)...

```console
sudo install -D -t /opt/cni/bin/ bin/*
```

## Install slirp4netns CNI plugin

Unlike the other components, `slirp4netns` is written in C and
requires the following dependencies on a Debian-based system...

```console
# if not installed yet...
$ sudo apt-get install build-essential autoconf

$ sudo apt-get install libglib2.0-dev libslirp-dev libcap-dev libseccomp-dev
```

Install by running the following from the folder you checked out
`github.com/rootless-containers/slirp4netns` into...

```console
$ ./autogen.sh
$ ./configure --prefix=/usr
$ make
$ sudo make install
```

## Install rootlesskit

In the checked out folder of
`github.com/rootless-containers/rootlesskit`, run...

```console
$ make
$ sudo make install
```

## Install buildkit

BuildKit is built using `docker buildx` via `Makefile`. These
instructions build the binaries manually. For some reason they choose
to disable optimization and function inlining in the compiler options
(`gcflags`) for all packages (`all=-N -l`) in the build `RUN`
statements in `Dockerfile`. It is safe to remove
`-gcflags='all=-N -l'` from the command below or keep it if you would
want to debug something using `dlv` and perhaps `gdlv`. From the
checked out folder of `github.com/moby/buildkit`...

```console
$ go build -gcflags 'all=-N -l' -ldflags "-extldflags '-static'" -tags "osusergo netgo static_build seccomp" ./cmd/buildkitd

$ go build -gcflags 'all=-N -l' -ldflags "-extldflags '-static'" ./cmd/buildctl

$ ldd buildkitd
        not a dynamic executable
$ ldd buildctl
        not a dynamic executable
```

Install them manually...

```console
$ sudo install -t /usr/local/bin/ buildkitd buildctl
```

## Install nerdctl

You should now have all the dependencies for running `containerd` and
BuildKit in rootless mode. `nerdctl` is a client to `containerd`
similar to `docker` or `podman` which will help you run containers
more easily than `runc`, for example. The full name is supposedly
*containerdctl*, not more nerdy than `docker` or `podman`. The
`nerdctl` Git repository feature two scripts for setting up
`containerd` and `buildkitd` in rootless mode. But first, let us build
and install `nerdctl`. From the folder you checked out
`github.com/containerd/nerdctl`, run...

```console
$ make
$ sudo make install
```

## Setup rootless containerd

Stay in `github.com/containerd/nerdctl` and look in the directory
`extras/rootless`. You will find two files:
`containerd-rootless-setuptool.sh` and `containerd-rootless.sh`,
install both under `/usr/local/bin`...

```console
sudo install -t /usr/local/bin/ extras/rootless/*
```

Now, run `containerd-rootless-setuptool.sh` as your regular user (or
the user you would want to run rootless containers)...

```console
$ containerd-rootless-setuptool.sh check
```

If you are *lucky*, there is only one `WARNING` regarding 

```
[INFO] Checking RootlessKit functionality
[INFO] Checking cgroup v2
[WARNING] The cgroup v2 controller "cpu" is not delegated for the current user ("/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/cgroup.controllers"), see https://rootlesscontaine.rs/getting-started/common/cgroup2/
[INFO] Checking overlayfs
[INFO] Requirements are satisfied
```

If you do not have the file `/sys/fs/cgroup/cgroup.controllers`, you
don't have cgroup v2 enabled in your kernel. Visit the link in the
output above for instructs how to enable it. The remainder of these
instructions assume cgroup v2 is enabled and the output is similar to
the following...

```console
$ cat /sys/fs/cgroup/cgroup.controllers 
cpuset cpu io memory hugetlb pids rdma misc
```

Let us delegate `cpu cpuset io memory pids` to the user, this is
required if you would like to set resource limits for your containers
(same as, for example `resources.limits.cpu` on containers in a pod
spec in Kubernetes).

The following commands can be found on
<https://rootlesscontaine.rs/getting-started/common/cgroup2/>. They do
three things: create `/etc/systemd/system/user@.service.d` (meaning
these will apply for all users of the system), create `delegate.conf`
with a service unit delegating control of `cpu`, `cpuset`, `io`,
`memory` and `pids` to users.

```console
$ sudo mkdir -p /etc/systemd/system/user@.service.d
$ cat <<EOF | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
[Service]
Delegate=cpu cpuset io memory pids
EOF
$ sudo systemctl daemon-reload
```

After running the above, the result from executing `containerd-rootless-setuptool.sh check`
should look like this...

```console
$ containerd-rootless-setuptool.sh check
[INFO] Checking RootlessKit functionality
[INFO] Checking cgroup v2
[INFO] Checking overlayfs
[INFO] Requirements are satisfied
```

We are now set to install user systemd units to start containerd...

```console
containerd-rootless-setuptool.sh install
```

There will be a bunch of output without any errors, and (hopefully)
your normal user should now have `containerd.service` running in
`systemd`...

```console
$ systemctl --user status containerd.service
```

`nerdctl` should now work as normal, try `nerdctl ps` or similar. Let's pull and run `busybox`...

```console
$ nerdctl run -ti --rm busybox:latest
docker.io/library/busybox:latest:                                                 resolved       |++++++++++++++++++++++++++++++++++++++|
index-sha256:ba76950ac9eaa407512c9d859cea48114eeff8a6f12ebaa5d32ce79d4a017dd8:    done           |++++++++++++++++++++++++++++++++++++++|
manifest-sha256:cca7bbfb3cd4dc1022f00cee78c51aa46ecc3141188f0dd520978a620697e7ad: done           |++++++++++++++++++++++++++++++++++++++|
config-sha256:9211bbaa0dbd68fed073065eb9f0a6ed00a75090a9235eca2554c62d1e75c58f:   done           |++++++++++++++++++++++++++++++++++++++|
layer-sha256:a307d6ecc6205dfa11d2874af9adb7e3fc244a429e00e8e3df90534d4cf0f3f8:    done           |++++++++++++++++++++++++++++++++++++++|
elapsed: 4.6 s                                                                    total:  2.1 Mi (473.6 KiB/s)
/ # id
uid=0(root) gid=0(root) groups=0(root),10(wheel)
/ # ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0@if5: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue 
    link/ether c2:9d:cf:2f:8d:26 brd ff:ff:ff:ff:ff:ff
    inet 10.4.0.3/24 brd 10.4.0.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::c09d:cfff:fe2f:8d26/64 scope link 
       valid_lft forever preferred_lft forever
/ # cat /etc/hostname 
26d4451faa50
/ # 
```

If you successfully ran `busybox`, congratulations, your 

## Install rootless buildkitd

In order to *rootlessly* build OCI container images, you need to run
`buildkitd` rootless. The rootless setup tool solves this conveniently
for us...

```console
$ containerd-rootless-setuptool.sh install-buildkit
```

```console
$ mkdir testimg
$ cd testimg
$ cat <<EOF > Containerfile
FROM busybox:latest
CMD echo hello
EOF
$ nerdctl build -t testing .
```

If the above command is successful, you should now have a `testing`
image ready to run...

```console
$ nerdctl image ls
REPOSITORY     TAG       IMAGE ID        CREATED               PLATFORM       SIZE        BLOB SIZE
testing        latest    e2d13f54d167    About a minute ago    linux/amd64    4.2 MiB     2.1 MiB

$ nerdctl run --rm testing
hello
$
```

## Enable lingering in systemd login manager

By default, `systemd` will terminate a user's running services when
there is no active session. To prevent `systemd` from terminating your
rootless `containerd` and all running containers, enable *lingering*
mode for users intended to run containers as service accounts...

```console
$ sudo loginctl enable-linger <your_rootless_username>
```

## Where do images end up?

In rootless mode, images end-up under `~/.local/share/containerd`,
specifically under `io.containerd.snapshotter.v1.overlayfs` unless you
need to use `fuse-overlayfs` or `native`.
