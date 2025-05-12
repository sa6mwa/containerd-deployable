#!/bin/bash
set -eo pipefail
set -x

VERSION="0.2"

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
meson build --default-library=static --prefix $(realpath output)
ninja -C build install
LIBSLIRP_PC=$(realpath output/lib/x86_64-linux-gnu/pkgconfig)
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
./configure --prefix=$OUT/usr LDFLAGS="-static" PKG_CONFIG_PATH="$LIBSLIRP_PC"
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

mkdir -p $OUT/usr/local/share/containerd
cat <<EOF > $OUT/usr/local/share/containerd/systemd-user.service
[Unit]
Description=User Manager for UID %i
After=systemd-user-sessions.service
# These are present in the RHEL8 version of this file except that the unit is Requires, not Wants.
# It's listed as Wants here so that if this file is used in a RHEL7 settings, it will not fail.
# If a user upgrades from RHEL7 to RHEL8, this unit file will continue to work until it's
# deleted the next time they upgrade Tableau Server itself.
After=user-runtime-dir@%i.service
Wants=user-runtime-dir@%i.service

[Service]
LimitNOFILE=infinity
LimitNPROC=infinity
User=%i
PAMName=systemd-user
Type=notify
# PermissionsStartOnly is deprecated and will be removed in future versions of systemd
# This is required for all systemd versions prior to version 231
PermissionsStartOnly=true
ExecStartPre=/bin/loginctl enable-linger %i
ExecStart=-/lib/systemd/systemd --user
Slice=user-%i.slice
KillMode=mixed
Delegate=yes
TasksMax=infinity
Restart=always
RestartSec=15

[Install]
WantedBy=default.target
EOF

cat <<EOF > $OUT/usr/local/bin/setup-rootless-containerd.sh
#!/bin/bash
set -uo pipefail

# https://rootlesscontaine.rs/getting-started/common/apparmor/
if [ ! -e /etc/apparmod.d/usr.local.bin.rootlesskit ]; then
	 echo "INFO: Configuring AppArmor, adding usr.local.bin.rootlesskit"
	 cat <<EOT | sudo tee "/etc/apparmor.d/usr.local.bin.rootlesskit"
abi <abi/4.0>,
include <tunables/global>

/usr/local/bin/rootlesskit flags=(unconfined) {
  userns,

  # Site-specific additions and overrides. See local/README for details.
  include if exists <local/usr.local.bin.rootlesskit>
}
EOT
	echo "INFO: Restarting apparmor.service"
	sudo systemctl restart apparmor.service
fi

echo "INFO: Running containerd-rootless-setuptool.sh check"

OUTPUT=\$(containerd-rootless-setuptool.sh check 2>&1)

set -e

if echo "\$OUTPUT" | grep -q -e ERROR -e WARNING; then
	if echo "\$OUTPUT" | grep -q "Needs systemd"; then
	 		echo "INFO: Copying /usr/local/share/containerd/systemd-user.service to /etc/systemd/system/user@\$(id -u).service"	
	 		sudo cp /usr/local/share/containerd/systemd-user.service /etc/systemd/system/user@\$(id -u).service
	 		echo "INFO: Running sudo systemctl daemon-reload"
	 		sudo systemctl daemon-reload
			echo "INFO: Running sudo systemctl enable user@\$(id -u).service"
			sudo systemctl enable user@\$(id -u).service
			echo "INFO: Running sudo systemctl start user@\$(id -u).service"
			sudo systemctl start user@\$(id -u).service
	fi

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
fi

echo "INFO: Running containerd-rootless-setuptool.sh install"
containerd-rootless-setuptool.sh install
systemctl --user status containerd.service

echo "INFO: Enabling lingering to keep containerd running after logout"
echo "INFO: Running sudo loginctl enable-linger \$(whoami)"
sudo loginctl enable-linger \$(whoami)

echo "INFO: To install buildkit, run the following command: containerd-rootless-setuptool.sh install-buildkit"
EOF
chmod 0755 $OUT/usr/local/bin/setup-rootless-containerd.sh

tar -cvzf containerd-deployable-${VERSION}.tar.gz --owner=root --group=root --transform 's/^out\///g' out/*

popd
