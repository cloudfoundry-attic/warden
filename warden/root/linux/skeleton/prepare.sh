#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

source ./common.sh

# Remove files we don't need or want
rm -f $target/var/cache/apt/archives/*.deb
rm -f $target/var/cache/apt/*cache.bin
rm -f $target/var/lib/apt/lists/*_Packages
rm -f $target/etc/ssh/ssh_host_*

write lib/init/fstab <<-EOS
# nothing
EOS

# Disable unneeded services
rm -f $target/etc/init/ureadahead*
rm -f $target/etc/init/plymouth*
rm -f $target/etc/init/hwclock*
rm -f $target/etc/init/hostname*
rm -f $target/etc/init/*udev*
rm -f $target/etc/init/module-*
rm -f $target/etc/init/mountall-*
rm -f $target/etc/init/mounted-*
rm -f $target/etc/init/dmesg*
rm -f $target/etc/init/network-*
rm -f $target/etc/init/procps*
rm -f $target/etc/init/rcS*

# Don't run ntpdate when container network comes up
rm -f $target/etc/network/if-up.d/ntpdate

# Don't run cpu frequency scaling
rm -f $target/etc/rc*.d/S*ondemand

# Disable selinux
mkdir -p $target/selinux
echo 0 > $target/selinux/enforce

# Remove console related upstart scripts
rm -f $target/etc/init/tty*
rm -f $target/etc/init/console-setup.conf

# Strip /dev down to the bare minimum
rm -rf $target/dev
mkdir -p $target/dev

# /dev/console
# This device is bind-mounted to a pty in the container, but keep it here so
# the container can use its permissions as reference.
file=$target/dev/console
mknod -m 600 $file c 5 1
chown root:tty $file

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
