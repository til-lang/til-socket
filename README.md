# til-socket

## Build

1. `make`

## Usage

```tcl
socket.tcp.server "*" 8000 | foreach connection {
    spawn {
        print "new connection: $connection"
        receive $connection | as data
        print " data: $data"
        send $connection [byte_vector 52 53 54]
        close $connection
    }
}
```
