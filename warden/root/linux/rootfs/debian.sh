#!/bin/bash -x

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob
shopt -s globstar

packages="openssh-server,rsync"
suite="testing"
mirror=$(grep "^deb" /etc/apt/sources.list | head -n1 | cut -d" " -f2)

# Fallback to default Ubuntu mirror when mirror could not be determined
if [ -z "$mirror" ]
then
  mirror="http://ftp.us.debian.org/debian/"
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
 $(which chroot) $target
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
deb http://ftp.de.debian.org/debian/ testing main contrib non-free
deb http://security.debian.org/ testing/updates main contrib non-free
EOS

# Disable interactive dpkg
chroot <<-EOS
echo debconf debconf/frontend select noninteractive |
 debconf-set-selections
EOS

# Set PATH
chroot <<-EOF
  export PATH=$PATH:/usr/local/sbin/:/usr/sbin/:/sbin/
EOF

# Update packages
chroot <<-EOS
apt-get update
EOS

# Generate and setup default locale (en_US.UTF-8)
chroot <<-EOS
apt-get install -y locales 
#echo "LANG=en_US.UTF-8" > /etc/default/locale
locale-gen en_US.UTF-8
#update-locale LANG="en_US.UTF-8"
EOS

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
