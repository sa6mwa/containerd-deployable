# containerd-deployable

The `build.sh` script in this repository builds all components necessary to run containerd in a rootless environment. The script is intended to be run on a system with a working Go installation. The script will download and build the following components:

* runc
* containerd
* nerdctl
* plugins <https://github.com/containernetworking/plugins>
* buildkit
* rootlesskit
* slirp4netns

All components will be statically linked and compressed into a tarball
for easy distribution. The tarball can be extracted under the root
directory of the target system and the binaries will end up in
`/usr/local/bin` and `/usr/bin`. CNI plugins will be installed in
`/opt/cni/bin`.

```console
$ ./build.sh
```

The script will create a tarball in the `build` directory. See the
release page for pre-built tarballs.

## Usage

Extract the tarball on the target system from the root directory.

```console
$ sudo tar -C / -xvzf containerd-deployable-0.2.tar.gz
```

Become a normal user you want to run containerd as and run...

```console
$ contrainerd-rootless-setuptool.sh check
[INFO] Checking RootlessKit functionality
[INFO] Checking cgroup v2
[INFO] Checking overlayfs
[INFO] Requirements are satisfied
```

The helper script `setup-rootless-containerd.sh` (located under
`usr/local/bin`) can be used to set up potentially missing systemd
units for delegating cpu, cpuset, etc to the user namespace. On most
modern systems, this is not necessary. If
`containerd-rootless-setuptool.sh` says everything is fine, the script
will run `containerd-rootless-setuptool.sh install` and enable
lingering mode for the user (`sudo loginctl enable-linger $(whoami)`).

When complete, you should be able to run a container image from
`docker.io`...

```console
$ nerdctl run --rm -ti busybox
docker.io/library/busybox:latest:                                                 resolved       |++++++++++++++++++++++++++++++++++++++| 
index-sha256:6d9ac9237a84afe1516540f40a0fafdc86859b2141954b4d643af7066d598b74:    done           |++++++++++++++++++++++++++++++++++++++| 
manifest-sha256:538721340ded10875f4710cad688c70e5d0ecb4dcd5e7d0c161f301f36f79414: done           |++++++++++++++++++++++++++++++++++++++| 
config-sha256:3f57d9401f8d42f986df300f0c69192fc41da28ccc8d797829467780db3dd741:   done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:9ad63333ebc97e32b987ae66aa3cff81300e4c2e6d2f2395cef8a3ae18b249fe:    done           |++++++++++++++++++++++++++++++++++++++| 
elapsed: 2.8 s                                                                    total:  2.1 Mi (777.9 KiB/s)                                     
/ # echo hello world
hello world
/ # 
```
