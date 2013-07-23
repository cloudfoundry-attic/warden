# Getting started on CentOS 6

TBD.

## Install dependencies

```
sudo yum install -y glibc-static
...
```

## Setup system

### SELinux

SELinux prevents warden from fully isolating a container's filesystem.
To make warden work on CentOS, SELinux needs to be entirely disabled, by
setting `SELINUX=disabled` in `/etc/selinux/config`.
Alternatively, it is possible that some set of SELinux policies can make the
combination work (this has not been confirmed to be possible).

### Networking

CentOS comes with a set of firewall rules that are too restrictive for warden
to work out of the box.
In particular, there is one rule that rejects all traffic in the `FORWARD`
chain on the `filter` table.
Traffic originating from containers goes through this chain and is rejected
immediately.
The entire set of firewall rules can be disabled by running
`/etc/init.d/iptables stop`, or should be tweaked such that it doesn't collide
with warden's networking requirements.

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

