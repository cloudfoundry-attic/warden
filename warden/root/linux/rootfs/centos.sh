#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob
shopt -s globstar

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

tmpdir=$(mktemp -d)
yumdownloader --destdir=$tmpdir centos-release
rpm -iv --nodeps --root $target $tmpdir/centos-release-*.rpm
rm -rf $tmpdir

yum -y --installroot $target install yum
yum -y --installroot $target groupinstall "Development Tools"
yum -y --installroot $target install zlib-devel
yum -y --installroot $target install openssl-devel
yum -y --installroot $target install readline-devel

# Only used for tests
yum -y --installroot $target install nc
