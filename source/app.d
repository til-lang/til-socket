import std.algorithm : remove;
import std.datetime : dur;

import til.nodes;

import std.socket;

CommandsMap connectionCommands;


class TcpSocketConnection : Item
{
    TcpSocketServer server;
    Socket connection;
    ubyte[1024] receiveBuffer;
    long receiveBufferSize;
    ubyte[1024] sendBuffer;
    long sendBufferSize;

    this(TcpSocketServer server, Socket connection)
    {
        this.server = server;
        this.connection = connection;
        this.commands = connectionCommands;
    }

    void close()
    {
        connection.close();
        server.remove(this);
    }

    override string toString()
    {
        auto address = connection.remoteAddress;
        auto ip = address.toAddrString;
        auto port = address.toPortString;
        return "TcpSocketConnection:" ~ ip ~ ":" ~ port;
    }
}


class TcpSocketServer : Item
{
    TcpSocket socket;
    TcpSocketConnection[] clients;
    SocketSet socketSet;

    this(string host, ushort port)
    {
        if (host == "*")
        {
            host = "0.0.0.0";
        }
        debug {stderr.writeln("new socket:", host, ":", port);}
        socket = new TcpSocket;
        assert(socket.isAlive);
        socket.blocking = false;
        socket.bind(new InternetAddress(host, port));
        socket.listen(64);
        debug {stderr.writeln("TcpSocketServer initialized.");}

        socketSet = new SocketSet(65);
    }
    void remove(TcpSocketConnection c)
    {
        foreach (index, client; clients)
        {
            if (client is c)
            {
                this.clients = clients.remove(index);
                debug {stderr.writeln("removed client ", index);}
                return;
            }
        }
        debug {stderr.writeln(" no client removed!");}
    }
    override Context next(Context context)
    {
        // TODO: split this into new methods!

        // This yield is coming in the foreach in
        // the next Til version:
        context.yield();

        // Send everything from each client.sendBuffer:
        foreach (index, client; clients)
        {
            if (client.sendBufferSize)
            {
                client.connection.send(
                    client.sendBuffer[0..client.sendBufferSize]
                );
                client.sendBufferSize = 0;
            }
        }

        // Receive new data into client.receiveBuffer:
        socketSet.reset();
        socketSet.add(socket);

        foreach (client; clients)
        {
            socketSet.add(client.connection);
        }

        auto n = Socket.select(socketSet, null, null, dur!"msecs"(5000));

        if (n == -1)
        {
            debug {stderr.writeln(" interrupted");}
            auto msg = "Socket was interrupted";
            // return context.error(msg, ErrorCode.Interrupted, "socket");
            return context.error(msg, ErrorCode.Unknown, "socket");
        }
        if (n == 0)
        {
            debug {stderr.writeln(" skipping");}
            context.exitCode = ExitCode.Skip;
            return context;
        }

        foreach (client; clients)
        {
            if (socketSet.isSet(client.connection))
            {
                // TODO: how to clean up the buffer or add to it
                // instead of simply overwriting?
                client.receiveBufferSize = client.connection.receive(
                    client.receiveBuffer[]
                );
                if (client.receiveBufferSize == Socket.ERROR)
                {
                    debug {stderr.writeln("SOCKET ERROR! ", client);}
                }
                else if (client.receiveBufferSize == 0)
                {
                    try
                    {
                        // if the connection closed due to an error, remoteAddress() could fail
                        // XXX: is it okay to ALWAYS call this method???
                        client.connection.remoteAddress();
                    }
                    catch (SocketException)
                    {
                        // writeln("Connection closed.");
                        this.remove(client);
                        context.exitCode = ExitCode.Skip;
                        return context;
                    }
                    continue;
                }
                else
                {
                    debug {
                        stderr.writeln(
                            " RECEIVED ",
                            client.receiveBufferSize,
                            " bytes: ",
                            client.receiveBuffer[0..client.receiveBufferSize]
                        );
                    }
                }
            }
        }

        if (socketSet.isSet(socket))
        {
            auto s = socket.accept();
            auto connection = new TcpSocketConnection(this, s);
            debug {stderr.writeln(" NEW CONNECTION:", connection);}
            // TODO: fix terminology. Is it a connection or a client???
            this.clients ~= connection;
            context.push(connection);
            context.exitCode = ExitCode.Continue;
            return context;
        }

        debug {stderr.writeln("SKIP");}
        context.exitCode = ExitCode.Skip;
        return context;
    }

    override string toString()
    {
        return "TcpSocketServer";
    }
}


extern (C) CommandsMap getCommands(Escopo escopo)
{
    CommandsMap commands;

    commands["tcp.server"] = new Command((string path, Context context)
    {
        string host = context.pop!string();
        long port = context.pop!long();
        auto server = new TcpSocketServer(host, cast(ushort)port);
        return context.push(server);
    });

    connectionCommands["send"] = new Command((string path, Context context)
    {
        auto connection = context.pop!TcpSocketConnection();
        auto data = context.pop!ByteVector();

        auto count = connection.connection.send(data.values);
        if (count == Socket.ERROR)
        {
            auto msg = "Socket error";
            return context.error(msg, ErrorCode.Unknown, "socket");
        }
        return context;
    });
    connectionCommands["receive"] = new Command((string path, Context context)
    {
        auto connection = context.pop!TcpSocketConnection();

        auto count = connection.connection.receive(connection.receiveBuffer);
        if (count == Socket.ERROR)
        {
            auto msg = "Socket error";
            return context.error(msg, ErrorCode.Unknown, "socket");
        }
        auto data = connection.receiveBuffer[0..count];
        context.push(new ByteVector(cast(byte[])data));
        /*
        auto vector = new ByteVector();
        vector.values = cast(byte[])data;
        context.push(vector);
        */
        return context;
    });
    connectionCommands["close"] = new Command((string path, Context context)
    {
        auto connection = context.pop!TcpSocketConnection();
        connection.close();
        return context;
    });
    // TODO: extractions: host, port, is_alive

    return commands;
}
