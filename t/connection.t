use strict;
use warnings;
use Test::More;
use Test::Exception;

use MojoX::MongoDB::Timestamp; # needed if db is being run as master

use MojoX::MongoDB;

my $conn;
eval {
    my $host = "localhost";
    if (exists $ENV{MONGOD}) {
        $host = $ENV{MONGOD};
    }
    $conn = MojoX::MongoDB::Connection->new(host => $host);
};

if ($@) {
    plan skip_all => $@;
}
else {
    plan tests => 19;
}

throws_ok {
    MojoX::MongoDB::Connection->new(host => 'localhost', port => 1);
} qr/couldn't connect to server/, 'exception on connection failure';

SKIP: {
    skip "connecting to default host/port won't work with a remote db", 6 if exists $ENV{MONGOD};

    lives_ok {
        $conn = MojoX::MongoDB::Connection->new;
    } 'successful connection';
    isa_ok($conn, 'MojoX::MongoDB::Connection');

    is($conn->host, 'mongodb://localhost:27017', 'host default value');

    # just make sure a couple timeouts work
    my $to = MojoX::MongoDB::Connection->new('timeout' => 1);
    $to = MojoX::MongoDB::Connection->new('timeout' => 123);
    $to = MojoX::MongoDB::Connection->new('timeout' => 2000000);

    # test conn format
    lives_ok {
        $conn = MojoX::MongoDB::Connection->new("host" => "mongodb://localhost:27017");
    } 'connected';

    lives_ok {
        $conn = MojoX::MongoDB::Connection->new("host" => "mongodb://localhost:27017,");
    } 'extra comma';

    lives_ok {
        $conn = MojoX::MongoDB::Connection->new("host" => "mongodb://localhost:27018,localhost:27019,localhost");
    } 'last in line';
}

my $db = $conn->get_database('test_database');
isa_ok($db, 'MojoX::MongoDB::Database', 'get_database');

$db->get_collection('test_collection')->insert({ foo => 42 }, {safe => 1});

ok((grep { $_ eq 'test_database' } $conn->database_names), 'database_names');

lives_ok {
    $db->drop;
} 'drop database';

ok(!(grep { $_ eq 'test_database' } $conn->database_names), 'database got dropped');


# w
SKIP: {
    is($conn->w, 1, "get w");
    $conn->w(3);
    is($conn->w, 3, "set w");

    is($conn->wtimeout, 1000, "get wtimeout");
    $conn->wtimeout(100);
    is($conn->wtimeout, 100, "set wtimeout");

    $db->drop;
}

# autoload
{
    my $db1 = $conn->foo;
    is($db1->name, "foo");
}

# query_timeout
{
    my $timeout = $MojoX::MongoDB::Cursor::timeout;

    my $conn2 = MojoX::MongoDB::Connection->new(auto_connect => 0);
    is($conn2->query_timeout, $timeout, 'query timeout');

    $MojoX::MongoDB::Cursor::timeout = 40;
    $conn2 = MojoX::MongoDB::Connection->new(auto_connect => 0);
    is($conn2->query_timeout, 40, 'query timeout');

    $MojoX::MongoDB::Cursor::timeout = $timeout;
}

# max_bson_size
{
    my $size = $conn->max_bson_size;
    my $result = $conn->admin->run_command({buildinfo => 1});
    if (exists $result->{'maxBsonObjectSize'}) {
        is($size, $result->{'maxBsonObjectSize'});
    }
    else {
        is($size, 4*1024*1024);
    }
}

END {
    if ($conn) {
        $conn->foo->drop;
    }
    if ($db) {
        $db->drop;
    }
}
