# warden-protocol

> This README describes the **protocol** library. Please refer to the top
> level [README][tlr] for an overview of all components.

[tlr]: /README.md

## Building
Generating the protocol buffer bindings requires a protocol buffer compiler.
If you're a homebrew user on the mac, you can use `brew install protobuf`; if
you're using another platform, please visit the
[protocol buffer project][protobuf] for information about how to download or
build the compiler.

Once you have `protoc` on your path:

1. `bundle`
1. `bundle exec rake build`

## Testing

Use `bundle exec rake spec` to execute the tests.

## License

The project is licensed under the Apache 2.0 license (see the
[`LICENSE`][license] file in the root directory of the repository).

[license]: /LICENSE
[protobuf]: https://code.google.com/p/protobuf
