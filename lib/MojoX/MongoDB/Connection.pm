package MojoX::MongoDB::Connection;
use Mojo::Base -base;

use MojoX::MongoDB;
use Digest::MD5;
use Tie::IxHash;
use boolean;

has host           => 'mongodb://localhost:27017';
has w              => 1;
has wtimeout       => 1000;
has port           => 27017;
has left_host      => sub { undef };
has left_port      => 27017;
has right_host     => sub { undef };
has right_port     => 27017;
has auto_reconnect => 1;
has auto_connect   => 1;
has timeout        => 20000;
has username       => sub { undef };
has password       => sub { undef };
has db_name        => 'admin';
has query_timeout  => sub { return $MojoX::MongoDB::Cursor::timeout };
has max_bson_size  => 4194304;
has find_master    => 0;

# hash of servers in a set
# call connected() to determine if a connection is enabled
has _servers => sub { {} };

# actual connection to a server in the set
has _master => sub { undef };

has ts => 0;

sub AUTOLOAD {
    my $self = shift @_;
    our $AUTOLOAD;

    my $db = $AUTOLOAD;
    $db =~ s/.*:://;

    return $self->get_database($db);
}

sub DESTROY { }

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    my @pairs;

    # deprecated syntax
    if ( !( $self->host =~ /^mongodb:\/\// ) ) {
        push @pairs, $self->host . ":" . $self->port;
    }

    # even more deprecated syntax
    elsif ( $self->left_host && $self->right_host ) {
        push @pairs, $self->left_host . ":" . $self->left_port;
        push @pairs, $self->right_host . ":" . $self->right_port;
    }

    # supported syntax
    else {
        my $str = substr $self->host, 10;
        @pairs = split ",", $str;
    }

    # a simple single server is special-cased (so we don't recurse forever)
    if ( @pairs == 1 && !$self->find_master ) {
        my ( $host, $port ) = split( /\:/, $pairs[0] );
        $self->_init_conn( $host, $port || 27017 );
        if ( $self->auto_connect ) {
            $self->connect;
            $self->max_bson_size( $self->_get_max_bson_size );
        }
        return $self;
    }

    # multiple servers
    my $connected = 0;
    foreach my $pair (@pairs) {
        my $server = $self->_servers->{$pair} = MojoX::MongoDB::Connection->new(
            host         => "mongodb://$pair",
            find_master  => 0,
            auto_connect => 0
        );

        next unless $self->auto_connect;

        # it's okay if we can't connect, so long as someone can
        eval {
            $server->connect;
            $server->max_bson_size( $server->_get_max_bson_size );
        };

        # at least one connection worked
        $connected = 1 if !$@;
    }

    my $master;

    if ( $self->auto_connect ) {

        # if we still aren't connected to anyone, give up
        if ( !$connected ) {
            die "couldn't connect to any servers listed: "
              . join( ",", @pairs );
        }

        $master = $self->get_master;
        if ( $master == -1 ) {
            die "couldn't find master";
        }
        else {
            $self->max_bson_size( $master->max_bson_size );
        }
    }
    else {

        # no auto-connect so just pick one.
        # if auto-reconnect is set then it will connect as needed
        ($master) = values %{ $self->_servers };
    }

    # create a struct that just points to the master's connection
    $self->_init_conn_holder($master);

    return $self;
}

sub _get_max_bson_size {
    my $self = shift;
    my $buildinfo =
      $self->get_database('admin')->run_command( { buildinfo => 1 } );
    my $max = $buildinfo->{'maxBsonObjectSize'};
    return $max || 4194304;
}

sub database_names {
    my ($self) = @_;
    my $ret =
      $self->get_database('admin')->run_command( { listDatabases => 1 } );
    return map { $_->{name} } @{ $ret->{databases} };
}

sub get_database {
    my ( $self, $database_name ) = @_;
    return MojoX::MongoDB::Database->new(
        _connection => $self,
        name        => $database_name,
    );
}

sub _get_a_specific_connection {
    my ( $self, $host ) = @_;

    if ( $self->_servers->{$host}->connected ) {
        return $self->_servers->{$host};
    }

    eval { $self->_servers->{$host}->connect; };

    if ( !$@ ) {
        return $self->_servers->{$host};
    }
    return 0;
}

sub _get_any_connection {
    my ($self) = @_;

    while ( my ( $key, $value ) = each( %{ $self->_servers } ) ) {
        my $conn = $self->_get_a_specific_connection($key);
        if ($conn) {
            return $conn;
        }
    }

    return 0;
}

sub get_master {
    my ($self) = @_;

    # return if the connection is paired the stupid old way
    if ( defined $self->left_host && defined $self->right_host ) {
        return $self->_old_stupid_paired_conn;
    }

    my $conn = $self->_get_any_connection();

    # if we couldn't connect to anything, just return
    if ( !$conn ) {
        return -1;
    }

    # a single server or list of servers
    if ( !$self->find_master ) {
        $self->_master($conn);
        return $self->_master;
    }

    # auto-detect master
    else {
        my $master =
          $conn->get_database('admin')->run_command( { "ismaster" => 1 } );

        # check for errors
        if ( ref($master) eq 'SCALAR' ) {
            return -1;
        }

        # if this is a replica set & we haven't renewed the host list in 1 sec
        if ( $master->{'hosts'} && time() > $self->ts ) {

            # update (or set) rs list
            for ( @{ $master->{'hosts'} } ) {
                if ( !$self->_servers->{$_} ) {
                    $self->_servers->{$_} = MojoX::MongoDB::Connection->new(
                        "host"       => "mongodb://$_",
                        auto_connect => 0
                    );
                }
            }
            $self->ts( time() );
        }

        # if this is the master, whether or not it's a replica set, return it
        if ( $master->{'ismaster'} ) {
            $self->_master($conn);
            return $self->_master;
        }
        elsif ( $self->find_master && exists $master->{'primary'} ) {
            my $primary =
              $self->_get_a_specific_connection( $master->{'primary'} );
            if ( !$primary ) {
                return -1;
            }

            # double-check that this is master
            my $result =
              $primary->get_database("admin")
              ->run_command( { "ismaster" => 1 } );
            if ( $result->{'ismaster'} ) {
                $self->_master($primary);
                return $self->_master;
            }
        }
    }

    return -1;
}

sub _old_stupid_paired_conn {
    my $self = shift;

    my ( $left, $right, $master );

    # check the left host
    eval {
        $left = MojoX::MongoDB::Connection->new(
            "host"  => $self->left_host,
            "port"  => $self->left_port,
            timeout => $self->timeout
        );
    };
    if ( !( $@ =~ m/couldn't connect to server/ ) ) {
        $master = $left->find_one( 'admin.$cmd', { ismaster => 1 } );
        if ( $master->{'ismaster'} ) {
            return 0;
        }
    }

    # check the right_host
    eval {
        $right = MojoX::MongoDB::Connection->new(
            "host"  => $self->right_host,
            "port"  => $self->right_port,
            timeout => $self->timeout
        );
    };
    if ( !( $@ =~ m/couldn't connect to server/ ) ) {
        $master = $right->find_one( 'admin.$cmd', { ismaster => 1 } );
        if ( $master->{'ismaster'} ) {
            return 1;
        }
    }

    # something went wrong
    return -1;
}

sub authenticate {
    my ( $self, $dbname, $username, $password, $is_digest ) = @_;
    my $hash = $password;

    # create a hash if the password isn't yet encrypted
    if ( !$is_digest ) {
        $hash = Digest::MD5::md5_hex("${username}:mongo:${password}");
    }

    # get the nonce
    my $db = $self->get_database($dbname);
    my $result = $db->run_command( { getnonce => 1 } );
    if ( !$result->{'ok'} ) {
        return $result;
    }

    my $nonce  = $result->{'nonce'};
    my $digest = Digest::MD5::md5_hex( $nonce . $username . $hash );

    # run the login command
    my $login = tie( my %hash, 'Tie::IxHash' );
    %hash = (
        authenticate => 1,
        user         => $username,
        nonce        => $nonce,
        key          => $digest
    );
    $result = $db->run_command($login);

    return $result;
}

1;

__END__

=head1 NAME

MojoX::MongoDB::Connection - A connection to a Mongo server

=head1 SYNOPSIS

The MojoX::MongoDB::Connection class creates a connection to the MojoX::MongoDB server.

By default, it connects to a single server running on the local machine
listening on the default port:

    # connects to localhost:27017
    my $connection = MojoX::MongoDB::Connection->new;

It can connect to a database server running anywhere, though:

    my $connection = MojoX::MongoDB::Connection->new(host => 'example.com:12345');

See the L</"host"> section for more options for connecting to MojoX::MongoDB.

=head2 Multithreading

Cloning instances of this class is disabled in Perl 5.8.7+, so forked threads
will have to create their own connections to the database.

=head1 DESCRIPTION

Please refer to the L<MongoDB> documentation and API for more information.

=head1 AUTHORS

  Kristina Chodorow <kristina@mongodb.org>
  minimalist <minimalist@lavabit.com>
