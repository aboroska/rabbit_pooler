rabbit_pooler
=============

RabbitMQ HA client with connection pool.

Work in progress. Very early stage, not tested yet!

It solves the problem of connecting to a broker in a RabbitMQ cluster and
automatically selecting another broker if the active connection is down.
Additionally it provides a connection pool for the channels.

Why does one want a pool of channels?

RabbitMQ [confirms](http://www.rabbitmq.com/confirms.html) that it received the message
by sending back an ack on the channel where the message was sent.
To send multiple messages on the same channel before receiving the ack the client
needs to track the count of the sent messages. To simplify things a new channel
can be used for a new message while the first channel is waiting for the confirmation
from the broker. By using a new channel for each message counting is not needed
and negative acknowledgments are trivially handled.
To limit the number of open channels a pool is needed. Pooler is used for this
purpose.

Why pooler? Why not poolboy which is simpler?

There are connections to be supervised and each connection has a pool of channels.
While poolboy is capable of supervising multiple pools of channels, it cannot
supervise the connections itself. Pooler can supervise both.

Build
-----

    $ rebar3 compile
