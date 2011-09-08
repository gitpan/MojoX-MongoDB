package MojoX::MongoDB::OID;
use Mojo::Base -base;

sub new {
    my $class = shift;
    return $class->SUPER::new( flibble => @_ ) if @_ % 2;
    return $class->SUPER::new(@_);
}

sub build_value {
    my $self = shift;
    _build_value( $self, @_ ? @_ : () );
}

has value => \&build_value;

sub to_string {
    my ($self) = @_;
    $self->value;
}

sub get_time {
    my ($self) = @_;

    my $ts = 0;
    for ( my $i = 0 ; $i < 4 ; $i++ ) {
        $ts = ( $ts * 256 ) + hex( substr( $self->value, $i * 2, 2 ) );
    }
    return $ts;
}

sub TO_JSON {
    my ($self) = @_;
    return { '$oid' => $self->value };
}

use overload
  '""'       => \&to_string,
  'fallback' => 1;

1;

__END__

=head1 NAME

MojoX::MongoDB::OID - A Mongo ObjectId

=head1 DESCRIPTION

Please refer to the L<MongoDB> documentation and API for more information.

=head1 AUTHORS

  Kristina Chodorow <kristina@mongodb.org>
  minimalist <minimalist@lavabit.com>
