package MojoX::MongoDB::Code;
use Mojo::Base -base;

has code  => sub { undef };
has scope => sub { undef };

1;

__END__

=head1 NAME

MojoX::MongoDB::Code - JavaScript code

=cut

=head1 ATTRIBUTES

=head2 code

A string of JavaScript code.

=head2 scope

An optional hash of variables to pass as the scope.

