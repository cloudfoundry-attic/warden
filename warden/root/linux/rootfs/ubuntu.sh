#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob
shopt -s globstar

packages="openssh-server,rsync"
suite="trusty"
mirror=$(grep "^deb" /etc/apt/sources.list | head -n1 | cut -d" " -f2)

# Fallback to default Ubuntu mirror when mirror could not be determined
if [ -z "$mirror" ]
then
  mirror="http://archive.ubuntu.com/ubuntu/"
fi

function debootstrap() {
  # -v is too new, revert to old trick
  # ${VAR+X} will be
  #   X     when VAR is unset
  #   $VAR  otherwise
  # Only do this heuristic when http_proxy is unset
  # You can opt out of this by setting http_proxy to nil
  if [ -z ${http_proxy+X} ]
  then
    eval $(apt-config shell http_proxy Acquire::http::Proxy)
    export http_proxy
  fi

  $(which debootstrap) --verbose --include $packages $suite $target $mirror
}

function write() {
  [ -z "$1" ] && return 1

  mkdir -p $target/$(dirname $1)
  cat > $target/$1
}

function chroot() {
  $(which chroot) $target env -i $(cat $target/etc/environment) /bin/bash
}

if [ $EUID -ne 0 ]
then
  echo "Sorry, you need to be root."
  exit 1
fi

if [ "$#" -ne 1 ]
then
  echo "Usage: setup.sh [TARGET DIRECTORY]"
  exit 1
fi

target=$1

if [ -d $target ]
then
  read -p "Target directory already exists. Erase it? "
  if [[ $REPLY =~ ^[Yy].*$ ]]
  then
    rm -rf $target
  else
    echo "Aborting..."
    exit 1
  fi
fi

mkdir -p $target

debootstrap

write "etc/apt/sources.list" <<-EOS
deb $mirror $suite main universe
deb $mirror $suite-updates main universe
EOS

# Disable interactive dpkg
chroot <<-EOS
echo debconf debconf/frontend select noninteractive |
 debconf-set-selections
EOS

# Generate and setup default locale (en_US.UTF-8)
chroot <<-EOS
locale-gen en_US.UTF-8
update-locale LANG="en_US.UTF-8"
EOS

# Update packages
chroot <<-EOS
apt-get update
EOS

# Disable initctl so that apt cannot start any daemons
mv $target/sbin/initctl $target/sbin/initctl.real
ln -s /bin/true $target/sbin/initctl
trap "mv $target/sbin/initctl.real $target/sbin/initctl" EXIT

# Upgrade upstart
chroot <<-EOS
apt-get install -y upstart
EOS

# If upstart was upgraded, make sure to disable it again
if [ ! -h $target/sbin/initctl ]
then
  mv $target/sbin/initctl $target/sbin/initctl.real
  ln -s /bin/true $target/sbin/initctl
fi

# Upgrade everything
chroot <<-EOS
apt-get upgrade -y
EOS

# Install packages
chroot <<-EOS
apt-get install -y build-essential
EOS

# Remove files we don't need or want
chroot <<-EOS
rm -f /var/cache/apt/archives/*.deb
rm -f /var/cache/apt/*cache.bin
rm -f /var/lib/apt/lists/*_Packages
rm -f /etc/ssh/ssh_host_*
EOS
