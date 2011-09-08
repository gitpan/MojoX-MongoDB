package MojoX::MongoDB::Timestamp;
use Mojo::Base -base;

has sec => sub { undef };
has inc => sub { undef };

1;

__END__

=head1 NAME

MojoX::MongoDB::Timestamp - Timestamp used for replication

=head1 DESCRIPTION

Please refer to the L<MongoDB> documentation and API for more information.

=head1 AUTHORS

  Kristina Chodorow <kristina@mongodb.org>
  minimalist <minimalist@lavabit.com>

