#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname $0)

source ./common.sh

# Defaults for debugging the setup script
id=${id:-test}
network_netmask=${network_netmask:-255.255.255.252}
network_host_ip=${network_host_ip:-10.0.0.1}
network_host_iface="w-${id}-0"
network_container_ip=${network_container_ip:-10.0.0.2}
network_container_iface="w-${id}-1"
user_uid=${user_uid:-10000}
rootfs_path=$(readlink -f $rootfs_path)

# Write configuration
cat > config <<-EOS
id=$id
network_netmask=$network_netmask
network_host_ip=$network_host_ip
network_host_iface=$network_host_iface
network_container_ip=$network_container_ip
network_container_iface=$network_container_iface
user_uid=$user_uid
rootfs_path=$rootfs_path
EOS

setup_fs $rootfs_path
trap "teardown_fs" EXIT

# Remove files we don't need or want
rm -f $target/var/cache/apt/archives/*.deb
rm -f $target/var/cache/apt/*cache.bin
rm -f $target/var/lib/apt/lists/*_Packages
rm -f $target/etc/ssh/ssh_host_*

# Strip /dev down to the bare minimum
rm -rf $target/dev
mkdir -p $target/dev

# /dev/tty
file=$target/dev/tty
mknod -m 666 $file c 5 0
chown root:tty $file

# /dev/random, /dev/urandom
file=$target/dev/random
mknod -m 666 $file c 1 8
chown root:root $file
file=$target/dev/urandom
mknod -m 666 $file c 1 9
chown root:root $file

# /dev/null, /dev/zero
file=$target/dev/null
mknod -m 666 $file c 1 3
chown root:root $file
file=$target/dev/zero
mknod -m 666 $file c 1 5
chown root:root $file

# /dev/fd, /dev/std{in,out,err}
pushd $target/dev > /dev/null
ln -s /proc/self/fd
ln -s fd/0 stdin
ln -s fd/1 stdout
ln -s fd/2 stderr
popd > /dev/null

cat > $target/etc/hostname <<-EOS
$id
EOS

cat > $target/etc/hosts <<-EOS
127.0.0.1 localhost
$network_container_ip $id
EOS

# Inherit nameserver(s)
cp /etc/resolv.conf $target/etc/

# Add vcap user if not already present
$(which chroot) $target env -i /bin/bash <<-EOS
if ! id vcap > /dev/null 2>&1
then
  useradd -mU -u $user_uid -s /bin/bash vcap
fi
EOS

# The `mesg` tool modifies permissions on stdin. Warden regularly passes a
# custom stdin, which makes `mesg` complain that stdin is not a tty. Instead of
# removing all occurances of `mesg`, we simply bind it to /bin/true.
$(which chroot) $target env -i /bin/bash <<-EOS
rm /usr/bin/mesg
ln -sf /bin/true /usr/bin/mesg
EOS
