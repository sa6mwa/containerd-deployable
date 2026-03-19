#!/bin/bash
set -Eeuo pipefail
set -x

VERSION="0.4"

: "${CGO_ENABLED:=0}"
export CGO_ENABLED

: "${GOFLAGS:=-trimpath}"
export GOFLAGS

: "${AUTO_INSTALL_DEPS:=0}"

readonly -a REQUIRED_COMMANDS=(
	autoconf
	automake
	gcc
	git
	go
	install
	make
	meson
	ninja
	pkg-config
	readelf
)

readonly -a REQUIRED_PKG_CONFIG=(
	glib-2.0
	libcap
	libseccomp
)

readonly -a APT_PACKAGES=(
	autoconf
	automake
	build-essential
	libcap-dev
	libglib2.0-dev
	libseccomp-dev
	libtool-bin
	meson
	ninja-build
	pkg-config
)

readonly -a REPOS=(
	runc
	containerd
	nerdctl
	plugins
	buildkit
	rootlesskit
	slirp4netns
	libslirp
)

declare -A REPO_URLS=(
	[runc]="https://github.com/opencontainers/runc.git"
	[containerd]="https://github.com/containerd/containerd.git"
	[nerdctl]="https://github.com/containerd/nerdctl.git"
	[plugins]="https://github.com/containernetworking/plugins.git"
	[buildkit]="https://github.com/moby/buildkit.git"
	[rootlesskit]="https://github.com/rootless-containers/rootlesskit.git"
	[slirp4netns]="https://github.com/rootless-containers/slirp4netns.git"
	[libslirp]="https://gitlab.freedesktop.org/slirp/libslirp.git"
)

# Pinned bill of materials. Update these deliberately and verify the full build.
declare -A REPO_REFS=(
	[runc]="v1.2.9"
	[containerd]="v2.1.6"
	[nerdctl]="v2.1.6"
	[plugins]="v1.9.1"
	[buildkit]="v0.26.3"
	[rootlesskit]="v2.3.6"
	[slirp4netns]="v1.3.3"
	[libslirp]="v4.9.1"
)

have_command() {
	command -v "$1" >/dev/null 2>&1
}

check_dependencies() {
	local missing=()
	local dep

	for dep in "${REQUIRED_COMMANDS[@]}"; do
		if ! have_command "$dep"; then
			missing+=("command:$dep")
		fi
	done

	for dep in "${REQUIRED_PKG_CONFIG[@]}"; do
		if ! pkg-config --exists "$dep"; then
			missing+=("pkg-config:$dep")
		fi
	done

	if [ "${#missing[@]}" -eq 0 ]; then
		return
	fi

	if [ "$AUTO_INSTALL_DEPS" = "1" ]; then
		if ! have_command sudo || ! have_command apt-get; then
			echo "ERROR: AUTO_INSTALL_DEPS=1 requires both sudo and apt-get" >&2
			exit 1
		fi

		sudo apt-get update
		sudo apt-get install -y "${APT_PACKAGES[@]}"

		missing=()
		for dep in "${REQUIRED_COMMANDS[@]}"; do
			if ! have_command "$dep"; then
				missing+=("command:$dep")
			fi
		done
		for dep in "${REQUIRED_PKG_CONFIG[@]}"; do
			if ! pkg-config --exists "$dep"; then
				missing+=("pkg-config:$dep")
			fi
		done
	fi

	if [ "${#missing[@]}" -ne 0 ]; then
		printf 'ERROR: missing build dependencies:\n' >&2
		printf '  %s\n' "${missing[@]}" >&2
		printf 'INFO: install the required packages manually or rerun with AUTO_INSTALL_DEPS=1 on Debian/Ubuntu.\n' >&2
		exit 1
	fi
}

ensure_repo() {
	local dir="$1"
	local url="$2"
	local ref="$3"

	if [ ! -d "$dir/.git" ]; then
		git clone --branch "$ref" --depth=1 "$url" "$dir"
		return
	fi

	git -C "$dir" fetch --depth=1 origin "refs/tags/${ref}:refs/tags/${ref}"
	git -C "$dir" checkout -q "$ref"
}

verify_packaged_binaries_static() {
	local staged_dirs=(
		"$OUT/usr/local/bin"
		"$OUT/usr/local/sbin"
		"$OUT/usr/bin"
		"$OUT/opt/cni/bin"
	)
	local -a offenders=()
	local path

	for path in "${staged_dirs[@]}"; do
		[ -d "$path" ] || continue

		while IFS= read -r -d '' bin; do
			# Shell helpers and other non-ELF executables are not linkable binaries.
			if ! readelf -h "$bin" >/dev/null 2>&1; then
				continue
			fi

			if readelf -l "$bin" 2>/dev/null | grep -q 'INTERP'; then
				offenders+=("${bin#$OUT/}")
			fi
		done < <(find "$path" -type f -executable -print0)
	done

	if [ "${#offenders[@]}" -ne 0 ]; then
		printf 'ERROR: dynamically linked binaries found in staged output:\n' >&2
		printf '  %s\n' "${offenders[@]}" >&2
		exit 1
	fi
}

check_dependencies

mkdir -p build
pushd build >/dev/null

OUT="$(pwd)/out"
PREFIX="$OUT/usr/local"
CNI_BIN="$OUT/opt/cni/bin"
mkdir -p "$PREFIX/bin" "$CNI_BIN"

for repo in "${REPOS[@]}"; do
	ensure_repo "$repo" "${REPO_URLS[$repo]}" "${REPO_REFS[$repo]}"
done

# build libslirp
pushd libslirp >/dev/null
meson setup build --wipe --default-library=static --prefix "$(realpath output)"
ninja -C build install
LIBSLIRP_PC="$(find "$(realpath output/lib)" -type d -name pkgconfig -print -quit)"
if [ -z "$LIBSLIRP_PC" ]; then
	echo "ERROR: could not locate libslirp pkg-config directory" >&2
	exit 1
fi
popd >/dev/null

# build runc
pushd runc >/dev/null
make static
make install PREFIX="$PREFIX"
popd >/dev/null

# build containerd
pushd containerd >/dev/null
CGO_ENABLED=0 make clean
CGO_ENABLED=0 make STATIC=1
make install PREFIX="$PREFIX"
popd >/dev/null

# build plugins
pushd plugins >/dev/null
GOFLAGS=-trimpath ./build_linux.sh
install -m 0755 -t "$CNI_BIN" bin/*
popd >/dev/null

# build slirp4netns
pushd slirp4netns >/dev/null
./autogen.sh
env PKG_CONFIG="pkg-config --static" \
	PKG_CONFIG_PATH="$LIBSLIRP_PC" \
	./configure --prefix="$OUT/usr" LDFLAGS="-static"
make
make install
popd >/dev/null

# build rootlesskit
pushd rootlesskit >/dev/null
CGO_ENABLED=0 make clean
CGO_ENABLED=0 make
make install DESTDIR="$OUT"
popd >/dev/null

# build buildkit
pushd buildkit >/dev/null
go build -gcflags 'all=-N -l' -ldflags "-extldflags '-static'" -tags "osusergo netgo static_build seccomp" ./cmd/buildkitd
go build -gcflags 'all=-N -l' -ldflags "-extldflags '-static'" ./cmd/buildctl
install -m 0755 -t "$PREFIX/bin" buildkitd buildctl
popd >/dev/null

# build nerdctl
pushd nerdctl >/dev/null
make
make install PREFIX="$PREFIX"
install -m 0755 -t "$PREFIX/bin" extras/rootless/*
popd >/dev/null

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

verify_packaged_binaries_static

tar -cvzf containerd-deployable-${VERSION}.tar.gz --owner=root --group=root --transform 's/^out\///g' out/*

popd >/dev/null
