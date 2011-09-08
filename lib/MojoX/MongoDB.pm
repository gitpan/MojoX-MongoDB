use strict;
use warnings;

package MojoX::MongoDB;

our $VERSION = '0.452';

use XSLoader;

use Carp;
use MojoX::MongoDB::Connection;
use MojoX::MongoDB::Cursor;
use MojoX::MongoDB::Database;
use MojoX::MongoDB::Cursor;
use MojoX::MongoDB::OID;
use MojoX::MongoDB::Timestamp;
use MojoX::MongoDB::DateTime;

XSLoader::load(__PACKAGE__, $VERSION, int rand(2 ** 24));

1;

=head1 NAME

MojoX::MongoDB - Mongo Driver for Perl Mojolicious

=head1 SYNOPSIS

    use MojoX::MongoDB;

    my $connection = MojoX::MongoDB::Connection->new(host => 'localhost', port => 27017);
    my $database   = $connection->foo;
    my $collection = $database->bar;
    my $id         = $collection->insert({ some => 'data' });
    my $data       = $collection->find_one({ _id => $id });

=head1 DESCRIPTION

This module uses the same code and API as L<MongoDB>. The only changes between L<MongoDB> and
this modules are:

=over

=item

The default datetime is changed from L<DateTime> to L<MojoX::MongoDB::DateTime>.
This will considerably speed up all queries to the Mongo database that contain
a date time object.

=item

L<Any::Moose> is replaced with L<Mojo::Base>

=back

Please refer to the L<MongoDB> documentation and API for more information.

=head1 AUTHORS

  Florian Ragwitz <rafl@debian.org>
  Kristina Chodorow <kristina@mongodb.org>
  minimalist <minimalist@lavabit.com>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2011 by 10Gen.

This is free software, licensed under:

The Apache License, Version 2.0, January 2004

