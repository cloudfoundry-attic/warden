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

yum -y --installroot $target install gcc gcc-c++ kernel-devel.x86_64 openssl-devel.x86_64  libxml2.x86_64 libxml2-devel.x86_64 libxslt.x86_64 libxslt-devel.x86_64  git.x86_64 sqlite.x86_64 ruby-sqlite3.x86_64 sqlite-devel.x86_64 unzip.x86_64 zip.x86_64 ruby-devel.x86_64 ruby-mysql.x86_64 mysql-devel.x86_64  curl-devel.x86_64 postgresql-libs.x86_64 postgresql-devel.x86_64 libcurl.x86_64 libcurl-devel.x86_64
