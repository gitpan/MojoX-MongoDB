package MojoX::MongoDB::DateTime;

use strict;
use warnings;
use DateTime;

use overload
  '==' => \&op_eq,
  'eq' => \&op_eq,
  '""' => sub { $_[0]->epoch };

sub new {
    return shift->from_epoch( epoch => time );
}

sub from_epoch {
    my $class = shift;
    my %arg = @_ == 1 ? %{$_[0]} : @_;
    bless \%arg, $class;
}

sub epoch { return shift->{epoch} }

sub millisecond { 0 }

sub dt {
    my $self = shift;
    return DateTime->from_epoch( epoch => $self->epoch );
}

sub op_eq {
    return ref( $_[0] ) eq ref( $_[1] ) && $_[0]->epoch == $_[1]->epoch;
}

1;

__END__

=head1 NAME

MojoX::MongoDB::DateTime

