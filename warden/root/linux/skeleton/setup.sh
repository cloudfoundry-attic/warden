#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname $0)

source ./lib/common.sh

# Defaults for debugging the setup script
id=${id:-test}
network_netmask=${network_netmask:-255.255.255.252}
network_host_ip=${network_host_ip:-10.0.0.1}
network_host_iface="w-${id}-0"
network_container_ip=${network_container_ip:-10.0.0.2}
network_container_iface="w-${id}-1"
user_uid=${user_uid:-10000}
group_gid=$user_uid
rootfs_path=$(readlink -f $rootfs_path)
allow_nested_warden=${allow_nested_warden:-false}

# Write configuration
cat > etc/config <<-EOS
id=$id
network_netmask=$network_netmask
network_host_ip=$network_host_ip
network_host_iface=$network_host_iface
network_container_ip=$network_container_ip
network_container_iface=$network_container_iface
user_uid=$user_uid
rootfs_path=$rootfs_path
allow_nested_warden=$allow_nested_warden
EOS

setup_fs

# Strip /dev down to the bare minimum
rm -rf mnt/dev/*

# /dev/tty
file=mnt/dev/tty
mknod -m 666 $file c 5 0
chown root:tty $file

# /dev/random, /dev/urandom
file=mnt/dev/random
mknod -m 666 $file c 1 8
chown root:root $file
file=mnt/dev/urandom
mknod -m 666 $file c 1 9
chown root:root $file

# /dev/null, /dev/zero
file=mnt/dev/null
mknod -m 666 $file c 1 3
chown root:root $file
file=mnt/dev/zero
mknod -m 666 $file c 1 5
chown root:root $file

# /dev/fd, /dev/std{in,out,err}
pushd mnt/dev > /dev/null
ln -s /proc/self/fd
ln -s fd/0 stdin
ln -s fd/1 stdout
ln -s fd/2 stderr
popd > /dev/null

# Add fuse group and device, so fuse can work inside the container
file=mnt/dev/fuse
mknod -m 666 $file c 10 229
$(which chroot) mnt env -i /bin/bash -l <<-EOS
if ! getent group fuse >/dev/null; then
  addgroup --system fuse
fi
# fix perms
chown root:fuse /dev/fuse
chmod uga+rw /dev/fuse
EOS

cat > mnt/etc/hostname <<-EOS
$id
EOS

cat > mnt/etc/hosts <<-EOS
127.0.0.1 localhost
$network_container_ip $id
EOS

# By default, inherit the nameserver from the host container.
#
# Exception: When the host's nameserver is set to localhost (127.0.0.1), it is
# assumed to be running its own DNS server and listening on all interfaces.
# In this case, the warden container must use the network_host_ip address
# as the nameserver.
if [[ "$(cat /etc/resolv.conf)" == "nameserver 127.0.0.1" ]]
then
  cat > mnt/etc/resolv.conf <<-EOS
nameserver $network_host_ip
EOS
else
  cp /etc/resolv.conf mnt/etc/
fi

old_user_uid=$(cat mnt/etc/passwd | grep 'vcap:' | cut -d ':' -f 3) 
old_group_gid=$(cat mnt/etc/group | grep 'vcap:' | cut -d ':' -f 3) 

$(which chroot) mnt env -i /bin/bash -l <<-EOS
if [ -z $old_group_gid ]
then
  groupadd -g $group_gid vcap
else
  groupmod -g $group_gid vcap 
  find / -group $old_group_gid -exec chgrp -h $group_gid {} \;
fi

if [ -z $old_user_uid ]
then
  useradd -m -u $user_uid -s /bin/bash -g $group_gid vcap
else
  usermod -u $user_uid -g $group_gid vcap
  find / -user $old_user_uid -exec chown -h $user_uid {} \;
fi
EOS

