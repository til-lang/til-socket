# til-socket

## Install

Use [til-pkg](https://github.com/til-lang/til-pkg) to install it easily:

```bash
$ til install socket
```

## Usage

```tcl
socket.tcp.server "*" 8000 | foreach connection {
    spawn {
        autoclose $connection
        print "new connection: $connection"

        receive $connection | to.string | as data
        print " received: $data"

        to.byte_vector "pong: $data" | send $connection
    }
}
```
