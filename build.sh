#!/bin/bash

set -euo pipefail

export CGO_ENABLED=0
export GOFLAGS=-trimpath

mkdir -p build
pushd build

sudo apt-get install build-essential autoconf libglib2.0-dev libcap-dev libseccomp-dev meson

OUT=$(pwd)/out
PREFIX=$OUT/usr/local
CNI_BIN=$OUT/opt/cni/bin
mkdir -p $PREFIX $CNI_BIN

repos=(
	"opencontainers/runc"
	"containerd/containerd"
	"containerd/nerdctl"
	"containernetworking/plugins"
	"moby/buildkit"
	"rootless-containers/rootlesskit"
	"rootless-containers/slirp4netns"
	"slirp/libslirp"
)

for repo in "${repos[@]}"; do
		if [ -d "$(basename ${repo})" ]; then
			echo "skipping ${repo}"
			continue
		fi
		if [ "${repo}" = "slirp/libslirp" ]; then
				git clone --depth=1 https://gitlab.freedesktop.org/${repo}.git
		else				
				git clone --depth=1 https://github.com/${repo}.git
		fi
done

# build libslirp
pushd libslirp
meson build --default-library=static
ninja -C build
LIBSLIRP_A=$(realpath build)
popd

# build runc
pushd runc
make static
make install PREFIX=$PREFIX
popd

# build containerd
pushd containerd
make
make install PREFIX=$PREFIX
popd

# build plugins
pushd plugins
GOFLAGS=-trimpath ./build_linux.sh
install -m 0755 -t $CNI_BIN bin/*
popd

# build slirp4netns
pushd slirp4netns
./autogen.sh
./configure --prefix=$OUT/usr LDFLAGS="-static -L${LIBSLIRP_A}"
make
make install
popd

# build rootlesskit
pushd rootlesskit
make
make install DESTDIR=$OUT
popd

# build buildkit
pushd buildkit
go build -gcflags 'all=-N -l' -ldflags "-extldflags '-static'" -tags "osusergo netgo static_build seccomp" ./cmd/buildkitd
go build -gcflags 'all=-N -l' -ldflags "-extldflags '-static'" ./cmd/buildctl
install -m 0755 -t $PREFIX/bin buildkitd buildctl
popd

# build nerdctl
pushd nerdctl
make
make install PREFIX=$PREFIX
install -m 0755 -t $PREFIX/bin extras/rootless/*
popd

cat <<EOF > $OUT/usr/local/bin/setup-rootless-containerd.sh
#!/bin/sh
set -euo pipefail
echo "INFO: Running containerd-rootless-setuptool.sh check"
if containerd-rootless-setuptool.sh check | grep -q WARNING; then
  if [ ! -e /sys/fs/cgroup/cgroup.controllers ]; then
	  echo "ERROR: /sys/fs/cgroup/cgroup.controllers does not exist"
	  exit 1
  fi
  if ! grep cpu /sys/fs/cgroup/cgroup.controllers | grep memory | grep cpuset | grep -q io; then
	  echo "ERROR: some cgroup controllers are not enabled"
	  echo "INFO: Enabling the missing cgroup controllers"
    sudo mkdir -p /etc/systemd/system/user@.service.d
		cat <<EOF2 | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
[Service]
Delegate=cpu cpuset io memory pids
EOF2
    echo "INFO: Running sudo systemctl daemon-reload"
		sudo systemctl daemon-reload
  fi
	if ! containerd-rootless-setuptool.sh check ; then
		echo "ERROR: containerd-rootless-setuptool.sh check failed"
		exit 1
	fi
  echo "INFO: Running containerd-rootless-setuptool.sh install"
  containerd-rootless-setuptool.sh install
	systemctl --user status containerd.service

	echo "INFO: Enabling lingering to keep containerd running after logout"
  echo "INFO: Running sudo loginctl enable-linger $(whoami)"
	sudo loginctl enable-linger $(whoami)
echo "INFO: To install buildkit, run the following command: containerd-rootless-setuptool.sh install-buildkit"
fi
EOF
chmod 0755 $OUT/usr/local/bin/setup-rootless-containerd.sh
