package MojoX::MongoDB::Collection;
use Mojo::Base -base;

use Tie::IxHash;
use boolean;
use Carp;

has _database => sub { undef };

has name => sub { undef };

has full_name => sub {
    my $self    = shift;
    my $name    = $self->name;
    my $db_name = $self->_database->name;
    return "${db_name}.${name}";
};

sub AUTOLOAD {
    my $self = shift @_;
    our $AUTOLOAD;

    my $coll = $AUTOLOAD;
    $coll =~ s/.*:://;

    return $self->_database->get_collection( $self->name . '.' . $coll );
}

sub DESTROY { }

sub to_index_string {
    my $keys = shift;

    my @name;
    if (   ref $keys eq 'ARRAY'
        || ref $keys eq 'HASH' )
    {

        while ( ( my $idx, my $d ) = each(%$keys) ) {
            push @name, $idx;
            push @name, $d;
        }
    }
    elsif ( ref $keys eq 'Tie::IxHash' ) {
        my @ks = $keys->Keys;
        my @vs = $keys->Values;

        for ( my $i = 0 ; $i < $keys->Length ; $i++ ) {
            push @name, $ks[$i];
            push @name, $vs[$i];
        }
    }
    else {
        confess 'expected Tie::IxHash, hash, or array reference for keys';
    }

    return join( "_", @name );
}

sub find {
    my ( $self, $query, $attrs ) = @_;

  # old school options - these should be set with MojoX::MongoDB::Cursor methods
    my ( $limit, $skip, $sort_by ) = @{ $attrs || {} }{qw/limit skip sort_by/};

    $limit ||= 0;
    $skip  ||= 0;

    my $q      = $query || {};
    my $conn   = $self->_database->_connection;
    my $ns     = $self->full_name;
    my $cursor = MojoX::MongoDB::Cursor->new(
        _connection => $conn,
        _ns         => $ns,
        _query      => $q,
        _limit      => $limit,
        _skip       => $skip
    );

    $cursor->_init;
    if ($sort_by) {
        $cursor->sort($sort_by);
    }
    return $cursor;
}

sub query {
    my ( $self, $query, $attrs ) = @_;

    return $self->find( $query, $attrs );
}

sub find_one {
    my ( $self, $query, $fields ) = @_;
    $query  ||= {};
    $fields ||= {};

    return $self->find($query)->limit(-1)->fields($fields)->next;
}

sub insert {
    my ( $self, $object, $options ) = @_;
    my ($id) = $self->batch_insert( [$object], $options );

    return $id;
}

sub batch_insert {
    my ( $self, $object, $options ) = @_;
    confess 'not an array reference' unless ref $object eq 'ARRAY';

    my $add_ids = 1;
    if ( $options->{'no_ids'} ) {
        $add_ids = 0;
    }

    my $conn = $self->_database->_connection;
    my $ns   = $self->full_name;

    my ( $insert, $ids ) =
      MojoX::MongoDB::write_insert( $ns, $object, $add_ids );
    if ( length($insert) > $conn->max_bson_size ) {
        Carp::croak( "insert is too large: "
              . length($insert)
              . " max: "
              . $conn->max_bson_size );
        return 0;
    }

    if ( defined($options) && $options->{safe} ) {
        my $ok = $self->_make_safe($insert);

        if ( !$ok ) {
            return 0;
        }
    }
    else {
        $conn->send($insert);
    }

    return $ids ? @$ids : $ids;
}

sub update {
    my ( $self, $query, $object, $opts ) = @_;

    # there used to be one option: upsert=0/1
    # now there are two, there will probably be
    # more in the future.  So, to support old code,
    # passing "1" will still be supported, but not
    # documentd, so we can phase that out eventually.
    #
    # The preferred way of passing options will be a
    # hash of {optname=>value, ...}
    my $flags = 0;
    if ( $opts && ref $opts eq 'HASH' ) {
        $flags |= $opts->{'upsert'} << 0
          if exists $opts->{'upsert'};
        $flags |= $opts->{'multiple'} << 1
          if exists $opts->{'multiple'};
    }
    else {
        $flags = !( !$opts );
    }

    my $conn = $self->_database->_connection;
    my $ns   = $self->full_name;

    my $update = MojoX::MongoDB::write_update( $ns, $query, $object, $flags );
    if ( $opts->{safe} ) {
        return $self->_make_safe($update);
    }

    if ( $conn->send($update) == -1 ) {
        $conn->connect;
        die("can't get db response, not connected");
    }

    return 1;
}

sub remove {
    my ( $self, $query, $options ) = @_;

    my ( $just_one, $safe );
    if ( defined $options && ref $options eq 'HASH' ) {
        $just_one = exists $options->{just_one} ? $options->{just_one} : 0;
        $safe     = exists $options->{safe}     ? $options->{safe}     : 0;
    }
    else {
        $just_one = $options || 0;
    }

    my $conn = $self->_database->_connection;
    my $ns   = $self->full_name;
    $query ||= {};

    my $remove = MojoX::MongoDB::write_remove( $ns, $query, $just_one );
    if ($safe) {
        return $self->_make_safe($remove);
    }

    if ( $conn->send($remove) == -1 ) {
        $conn->connect;
        die("can't get db response, not connected");
    }

    return 1;
}

sub ensure_index {
    my ( $self, $keys, $options, $garbage ) = @_;
    my $ns = $self->full_name;

    # we need to use the crappy old api if...
    #  - $options isn't a hash, it's a string like "ascending"
    #  - $keys is a one-element array: [foo]
    #  - $keys is an array with more than one element and the second
    #    element isn't a direction (or at least a good one)
    #  - Tie::IxHash has values like "ascending"
    if (
        ( $options && ref $options ne 'HASH' )
        || ( ref $keys eq 'ARRAY'
            && ( $#$keys == 0 || $#$keys >= 1 && !( $keys->[1] =~ /-?1/ ) ) )
        || ( ref $keys eq 'Tie::IxHash' && $keys->[2][0] =~ /(de|a)scending/ )
      )
    {
        Carp::croak("you're using the old ensure_index format, please upgrade");
    }

    my $obj = Tie::IxHash->new( "ns" => $ns, "key" => $keys );

    if ( exists $options->{name} ) {
        $obj->Push( "name" => $options->{name} );
    }
    else {
        $obj->Push(
            "name" => MojoX::MongoDB::Collection::to_index_string($keys) );
    }

    if ( exists $options->{unique} ) {
        $obj->Push(
            "unique" => ( $options->{unique} ? boolean::true : boolean::false )
        );
    }
    if ( exists $options->{drop_dups} ) {
        $obj->Push( "dropDups" =>
              ( $options->{drop_dups} ? boolean::true : boolean::false ) );
    }
    if ( exists $options->{background} ) {
        $obj->Push( "background" =>
              ( $options->{background} ? boolean::true : boolean::false ) );
    }
    $options->{'no_ids'} = 1;

    my ( $db, $coll ) = $ns =~ m/^([^\.]+)\.(.*)/;

    my $indexes = $self->_database->get_collection("system.indexes");
    return $indexes->insert( $obj, $options );
}

sub _make_safe {
    my ( $self, $req ) = @_;
    my $conn = $self->_database->_connection;
    my $db   = $self->_database->name;

    my $last_error = Tie::IxHash->new(
        getlasterror => 1,
        w            => $conn->w,
        wtimeout     => $conn->wtimeout
    );
    my ( $query, $info ) =
      MojoX::MongoDB::write_query( $db . '.$cmd', 0, 0, -1, $last_error );

    $conn->send("$req$query");

    my $cursor = MojoX::MongoDB::Cursor->new(
        _ns         => $info->{ns},
        _connection => $conn,
        _query      => {}
    );
    $cursor->_init;
    $cursor->_request_id( $info->{'request_id'} );

    $conn->recv($cursor);
    $cursor->started_iterating(1);

    my $ok = $cursor->next();

    # $ok->{ok} is 1 if err is set
    Carp::croak $ok->{err} if $ok->{err};

    # $ok->{ok} == 0 is still an error
    if ( !$ok->{ok} ) {
        Carp::croak $ok->{errmsg};
    }

    return $ok;
}

sub save {
    my ( $self, $doc, $options ) = @_;

    if ( exists $doc->{"_id"} ) {

        if ( !$options || !ref $options eq 'HASH' ) {
            $options = { "upsert" => boolean::true };
        }
        else {
            $options->{'upsert'} = boolean::true;
        }

        return $self->update( { "_id" => $doc->{"_id"} }, $doc, $options );
    }
    else {
        return $self->insert( $doc, $options );
    }
}

sub count {
    my ( $self, $query ) = @_;
    $query ||= {};

    my $obj;
    eval {
        $obj = $self->_database->run_command(
            {
                count => $self->name,
                query => $query,
            }
        );
    };

    # if there was an error, check if it was the "ns missing" one that means the
    # collection hasn't been created or a real error.
    if ($@) {

        # if the request timed out, $obj might not be initialized
        if ( $obj && $obj =~ m/^ns missing/ ) {
            return 0;
        }
        else {
            die $@;
        }
    }

    return $obj->{n};
}

sub validate {
    my ( $self, $scan_data ) = @_;
    $scan_data = 0 unless defined $scan_data;
    my $obj = $self->_database->run_command( { validate => $self->name } );
}

sub drop_indexes {
    my ($self) = @_;
    return $self->drop_index('*');
}

sub drop_index {
    my ( $self, $index_name ) = @_;
    my $t = tie( my %myhash, 'Tie::IxHash' );
    %myhash = ( "deleteIndexes" => $self->name, "index" => $index_name );
    return $self->_database->run_command($t);
}

sub get_indexes {
    my ($self) = @_;
    return $self->_database->get_collection('system.indexes')
      ->query( { ns => $self->full_name, } )->all;
}

sub drop {
    my ($self) = @_;
    $self->_database->run_command( { drop => $self->name } );
    return;
}

1;

__END__

=head1 NAME

MojoX::MongoDB::Collection - A Mongo collection

=head1 SYNOPSIS

An instance of a MojoX::MongoDB collection.

    # gets the foo collection
    my $collection = $db->foo;

Collection names can be chained together to access sub-collections.  For
instance, the collection C<foo.bar> can be accessed with:

    my $collection = $db->foo->bar;

You can also access collections with the L<MojoX::MongoDB::Database/get_collection>
method.

=head1 DESCRIPTION

Please refer to the L<MongoDB> documentation and API for more information.

=head1 AUTHORS

  Kristina Chodorow <kristina@mongodb.org>
  minimalist <minimalist@lavabit.com>
