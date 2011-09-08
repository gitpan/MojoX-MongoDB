package MojoX::MongoDB::Cursor;
use Mojo::Base -base;

use boolean;
use Tie::IxHash;
use Carp;

$MojoX::MongoDB::Cursor::_request_id = int( rand(1000000) );
$MojoX::MongoDB::Cursor::slave_okay  = 0;
$MojoX::MongoDB::Cursor::timeout     = 30000;

has started_iterating => 0;
has _connection       => sub { undef };
has _ns               => sub { undef };
has _query            => sub { undef };
has _fields           => sub { {} };
has _limit            => 0;
has _skip             => 0;
has immortal          => 0;
has tailable          => 0;
has partial           => 0;
has slave_okay        => 0;
has _request_id       => 0;

# stupid hack for inconsistent database handling of queries
has _grrrr => 0;

sub _ensure_special {
    my ($self) = @_;

    if ( $self->_grrrr ) {
        return;
    }

    $self->_grrrr(1);
    $self->_query( { 'query' => $self->_query } );
}

# this does the query if it hasn't been done yet
sub _do_query {
    my ($self) = @_;

    if ( $self->started_iterating ) {
        return;
    }

    my $opts =
      ( $self->tailable << 1 ) |
      ( ( $MojoX::MongoDB::Cursor::slave_okay | $self->slave_okay ) << 2 ) |
      ( $self->immortal << 4 ) | ( $self->partial << 7 );

    my ( $query, $info ) = MojoX::MongoDB::write_query(
        $self->_ns,    $opts,         $self->_skip,
        $self->_limit, $self->_query, $self->_fields
    );
    $self->_request_id( $info->{'request_id'} );

    $self->_connection->send($query);
    $self->_connection->recv($self);

    $self->started_iterating(1);
}

sub fields {
    my ( $self, $f ) = @_;
    confess "cannot set fields after querying"
      if $self->started_iterating;
    confess 'not a hash reference'
      unless ref $f eq 'HASH';

    $self->_fields($f);
    return $self;
}

sub sort {
    my ( $self, $order ) = @_;
    confess "cannot set sort after querying"
      if $self->started_iterating;
    confess 'not a hash reference'
      unless ref $order eq 'HASH' || ref $order eq 'Tie::IxHash';

    $self->_ensure_special;
    $self->_query->{'orderby'} = $order;
    return $self;
}

sub limit {
    my ( $self, $num ) = @_;
    confess "cannot set limit after querying"
      if $self->started_iterating;

    $self->_limit($num);
    return $self;
}

sub skip {
    my ( $self, $num ) = @_;
    confess "cannot set skip after querying"
      if $self->started_iterating;

    $self->_skip($num);
    return $self;
}

sub snapshot {
    my ($self) = @_;
    confess "cannot set snapshot after querying"
      if $self->started_iterating;

    $self->_ensure_special;
    $self->_query->{'$snapshot'} = 1;
    return $self;
}

sub hint {
    my ( $self, $index ) = @_;
    confess "cannot set hint after querying"
      if $self->started_iterating;
    confess 'not a hash reference'
      unless ref $index eq 'HASH';

    $self->_ensure_special;
    $self->_query->{'$hint'} = $index;
    return $self;
}

sub explain {
    my ($self) = @_;
    my $temp = $self->_limit;
    if ( $self->_limit > 0 ) {
        $self->_limit( $self->_limit * -1 );
    }

    $self->_ensure_special;
    $self->_query->{'$explain'} = boolean::true;

    my $retval = $self->reset->next;
    $self->reset->limit($temp);

    undef $self->_query->{'$explain'};

    return $retval;
}

sub count {
    my ( $self, $all ) = @_;

    my ( $db, $coll ) = $self->_ns =~ m/^([^\.]+)\.(.*)/;
    my $cmd = new Tie::IxHash( count => $coll );

    if ( $self->_grrrr ) {
        $cmd->Push( query => $self->_query->{'query'} );
    }
    else {
        $cmd->Push( query => $self->_query );
    }

    if ($all) {
        $cmd->Push( limit => $self->_limit ) if $self->_limit;
        $cmd->Push( skip  => $self->_skip )  if $self->_skip;
    }

    my $result = $self->_connection->get_database($db)->run_command($cmd);

    # returns "ns missing" if collection doesn't exist
    return 0 unless ref $result eq 'HASH';
    return $result->{'n'};
}

sub all {
    my ($self) = @_;
    my @ret;

    while ( my $entry = $self->next ) {
        push @ret, $entry;
    }

    return @ret;
}

1;

__END__

=head1 NAME

MojoX::MongoDB::Cursor - A cursor/iterator for Mongo query results

=head1 SYNOPSIS

    while (my $object = $cursor->next) {
        ...
    }

    my @objects = $cursor->all;


=head1 DESCRIPTION

Please refer to the L<MongoDB> documentation and API for more information.

=head1 AUTHORS

  Kristina Chodorow <kristina@mongodb.org>
  minimalist <minimalist@lavabit.com>
