[![Code Climate](https://codeclimate.com/github/cloudfoundry/warden.png)](https://codeclimate.com/github/cloudfoundry/warden)

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

## License

The project is licensed under the Apache 2.0 license (see the
[`LICENSE`][license] file).

[license]: /LICENSE
