package MojoX::MongoDB::Database;
use Mojo::Base -base;

use MojoX::MongoDB::Collection;
use MojoX::MongoDB::GridFS;

has _connection => sub { undef };

has name => sub { undef };

sub AUTOLOAD {
    my $self = shift @_;
    our $AUTOLOAD;

    my $coll = $AUTOLOAD;
    $coll =~ s/.*:://;

    return $self->get_collection($coll);
}

sub DESTROY { }

sub collection_names {
    my ($self) = @_;
    my $it = $self->get_collection('system.namespaces')->query( {} );
    return
      map { substr( $_, length( $self->name ) + 1 ) }
      map { $_->{name} } $it->all;
}

sub get_collection {
    my ( $self, $collection_name ) = @_;
    return MojoX::MongoDB::Collection->new(
        _database => $self,
        name      => $collection_name,
    );
}

sub get_gridfs {
    my ( $self, $prefix ) = @_;
    $prefix = "fs" unless $prefix;

    return MojoX::MongoDB::GridFS->new(
        _database => $self,
        prefix    => $prefix
    );
}

sub drop {
    my ($self) = @_;
    return $self->run_command( { 'dropDatabase' => 1 } );
}

sub last_error {
    my ( $self, $options ) = @_;

    my $cmd = Tie::IxHash->new( "getlasterror" => 1 );
    if ($options) {
        $cmd->Push( "w",        $options->{w} )        if $options->{w};
        $cmd->Push( "wtimeout", $options->{wtimeout} ) if $options->{wtimeout};
        $cmd->Push( "fsync",    $options->{fsync} )    if $options->{fsync};
    }

    return $self->run_command($cmd);
}

sub run_command {
    my ( $self, $command ) = @_;
    my $obj = $self->get_collection('$cmd')->find_one($command);
    return $obj if $obj->{ok};
    $obj->{'errmsg'};
}

sub eval {
    my ( $self, $code, $args ) = @_;

    my $cmd = tie( my %hash, 'Tie::IxHash' );
    %hash = (
        '$eval' => $code,
        'args'  => $args
    );

    my $result = $self->run_command($cmd);
    if ( ref $result eq 'HASH' && exists $result->{'retval'} ) {
        return $result->{'retval'};
    }
    else {
        return $result;
    }
}

1;

__END__

=head1 NAME

MojoX::MongoDB::Database - A Mongo database

=head1 SYNOPSIS

The MojoX::MongoDB::Database class accesses to a database.

    # accesses the foo database
    my $db = $connection->foo;

=head1 DESCRIPTION

Please refer to the L<MongoDB> documentation and API for more information.

=head1 AUTHORS

  Kristina Chodorow <kristina@mongodb.org>
  minimalist <minimalist@lavabit.com>
