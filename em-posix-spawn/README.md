# `em-posix-spawn`

This module provides an interface to `POSIX::Spawn` for EventMachine. In
particular, it contains an EventMachine equivalent to `POSIX::Spawn::Child`.
This class encapsulates writing to the child process its stdin and reading from
both its stdout and stderr. Only when the process has exited, it triggers a
callback to notify others of its completion. Just as `POSIX::Spawn::Child`,
this module allows the caller to include limits for execution time and number
of bytes read from stdout and stderr.

# Usage

Please refer to the documentation of `POSIX::Spawn::Child` for the complete set
of options that can be passed when creating `Child`.

```ruby
require "em/posix/spawn"

EM.run {
  p = EM::POSIX::Spawn::Child.new("echo something")

  p.callback {
    puts "Child process echo'd: #{p.out.inspect}"
    EM.stop
  }

  p.errback { |err|
    puts "Error running child process: #{err.inspect}"
    EM.stop
  }

  # Add callbacks to listen to the child process' output streams.
  listeners = p.add_streams_listener { |listener, data|
    # Do something with the data.
    # Use listener.name to get the name of the stream.
    # Use listener.closed? to check if listener is closed.
    # This block is called exactly once after the listener is closed.
  }

  # Optionally, wait for all the listeners to be closed.
  while !listeners.all?(&:closed?) {
    ...
  }

  # Sends SIGTERM to the process, and SIGKILL after 5 seconds.
  # Returns true if this kill was successful, false otherwise.
  # The timeout is optional, default timeout is 0 (immediate SIGKILL
  # after SIGTERM).
  p.kill(5)
}
```

# Credit

The implementation for `EM::POSIX::Spawn::Child` and its tests are based on the
implementation and tests for `POSIX::Spawn::Child`, which is Copyright (c) 2011
by Ryan Tomayko <r@tomayko.com> and Aman Gupta <aman@tmm1.net>.
