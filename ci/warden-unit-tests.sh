#!/bin/bash

source dea-hm-workspace/src/warden/ci/warden-setup.sh

setup_warden_infrastructure

apt-get update
apt-get install -y iptables quota --no-install-recommends

source ~/.bashrc

export PATH=$PATH:/sbin

git config --system user.email "nobody@example.com"
git config --system user.name "Anonymous Coward"

rm -f dea-hm-workspace/bin/*
rm -rf dea-hm-workspace/src/dea_next/go/{bin,pkg}/*
export GOPATH=$PWD/dea-hm-workspace
export PATH=$PATH:$GOPATH/bin:$HOME/bin

wget -O /tmp/rootfs.tar.gz https://cf-release-blobs.s3.amazonaws.com/e23f42d7-4166-43e3-ba8c-99712048c1a9
mkdir -p /tmp/warden/rootfs
tar -xf /tmp/rootfs.tar.gz -C /tmp/warden/rootfs

trap "kill -9 ${dea_pid}; kill -9 ${warden_pid}; umount /tmp/warden/containers; umount /tmp/warden/rootfs; losetup -d ${rootfs_loopdev} || true; losetup -d ${containers_loopdev} || true" EXIT

exec 0>&-
cd dea-hm-workspace/src/warden/warden
chruby $(cat ../.ruby-version)
gem install bundler
bundle install
bundle exec rake setup:bin
bundle exec rake spec
