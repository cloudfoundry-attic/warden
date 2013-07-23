# Getting started on Ubuntu Lucid (10.04)

This short guide assumes Ruby 1.9 and Bundler are already available. Ensure that
Ruby 1.9 has GNU readline library support through the package: 'libreadline-dev'
and zlib support through the 'zlib1g-dev' package.

## Install the right kernel

If you are running Ubuntu 10.04 (Lucid), make sure the backported Natty
kernel is installed. After installing, reboot the system before
continuing.

```
sudo apt-get install -y linux-image-generic-lts-backport-natty
```

## Install dependencies

```
sudo apt-get install -y build-essential
sudo apt-get install -y debootstrap
sudo apt-get install -y quota
```

## Setup Warden

Run the setup routine, which compiles the C code bundled with Warden and
sets up the base file system for Linux containers.

```
sudo bundle exec rake setup[config/linux.yml]
```

> If `sudo` complains that `bundle` cannot be found, try `sudo
> env PATH=$PATH` to pass your current `PATH` to the `sudo` environment.

The setup routine sets up the file system for the containers at the directory
path specified under the key: `server -> container_rootfs_path` in the
config file: config/linux.yml.

## Run Warden

```
sudo bundle exec rake warden:start[config/linux.yml]
```

## Interact with Warden

```
bundle exec bin/warden
```
