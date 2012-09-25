#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

source ./common.sh

# Defaults for debugging the setup script
id=${id:-test}
network_netmask=${network_netmask:-255.255.255.252}
network_host_ip=${network_host_ip:-10.0.0.1}
network_host_iface="w-${id}-0"
network_container_ip=${network_container_ip:-10.0.0.2}
network_container_iface="w-${id}-1"
user_uid=${user_uid:-10000}
rootfs_path=$rootfs_path

# Write configuration
cat > config <<-EOS
id=${id}
network_netmask=${network_netmask}
network_host_ip=${network_host_ip}
network_host_iface=${network_host_iface}
network_container_ip=${network_container_ip}
network_container_iface=${network_container_iface}
user_uid=${user_uid}
EOS

setup_fs ${rootfs_path}
trap "teardown_fs" EXIT

./prepare.sh

write "etc/hostname" <<-EOS
${id}
EOS

write "etc/hosts" <<-EOS
127.0.0.1 ${id} localhost
${network_host_ip} host
${network_container_ip} container
EOS

write "etc/network/interfaces" <<-EOS
auto lo
iface lo inet loopback
auto ${network_container_iface}
iface ${network_container_iface} inet static
  gateway ${network_host_ip}
  address ${network_container_ip}
  netmask ${network_netmask}
EOS

# Inherit nameserver(s)
cp /etc/resolv.conf ${target}/etc/

# Add vcap user if not already present
chroot <<-EOS
if ! id vcap > /dev/null 2>&1
then
useradd -mU -u ${user_uid} -s /bin/bash vcap
fi
EOS

# Copy override directory
cp -r override/* ${target}/
chmod 700 ${target}/sbin/warden-*

# Remove things we don't use
rm -rf ${target}/etc/init.d
rm -rf ${target}/etc/rc*
rm -f ${target}/etc/init/control-alt-delete.conf
rm -f ${target}/etc/init/rc.conf
rm -f ${target}/etc/init/rc-sysinit.conf
rm -f ${target}/etc/init/cron*
rm -f ${target}/etc/network/if-up.d/openssh*

# The `mesg` tool modifies permissions on stdin. Warden regularly passes a
# custom stdin, which makes `mesg` complain that stdin is not a tty. Instead of
# removing all occurances of `mesg`, we simply bind it to /bin/true.
chroot <<EOS
rm /usr/bin/mesg
ln -s /bin/true /usr/bin/mesg
EOS
