# warden

Manages isolated, ephemeral, and resource controlled environments.

## Introduction

The project's primary goal is to provide a simple API for managing
isolated environments. These isolated environments -- or _containers_ --
can be limited in terms of CPU usage, memory usage, disk usage, and
network access. As of writing, the only supported OS is Linux.

## Components

This repository contains the following components:

* `warden` -- server
* `warden-protocol` -- protocol definition, used by both the server and clients
* `warden-client` -- client (Ruby)
* `em-warden-client` -- client (Ruby's EventMachine)

For information on how to run the warden server and interact with it
at the command line, see the [warden server README](warden/README.md).

## Testing

Warden server tests are run automatically in a newly created container using
a virtualbox image dynamically downloaded from
`s3.amazonaws.com/runtime-artifacts/warden-compatible.box`.

```bash
# Checkout the repos
git clone https://github.com/cloudfoundry/warden
```

There is a `.ruby-version` file in the root of the repo which is copied into
the created container filespace (along with the rest of the `warden`
directory, with a few exceptions). The version in this file is that used
in the container. This is pre-installed in the `warden-compatible.box` image.

To run `bin/test_in_vm` you need to have this exact same version of ruby
installed locally.

```bash
# Run warden server tests
bin/test_in_vm
```

## License

The project is licensed under the Apache 2.0 license (see the
[`LICENSE`][license] file).

[license]: /LICENSE

## Contributing

Please read the [contributors' guide](https://github.com/cloudfoundry/warden/blob/master/CONTRIBUTING.md).
