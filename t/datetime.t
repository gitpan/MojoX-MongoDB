use strict;
use warnings;

use Test::More tests => 5;

use MojoX::MongoDB;
use DateTime;

my $conn = MojoX::MongoDB::Connection->new();
my $db = $conn->get_database('foo');
my $c = $db->get_collection('bar');

my $now = time;
my $dt = DateTime->from_epoch( epoch => $now );
my $md = MojoX::MongoDB::DateTime->from_epoch( epoch => $now );

$c->insert({dt => $dt, md => $md});
my $r = $c->find_one;
ok($r, 'found');
isa_ok($r->{dt}, 'MojoX::MongoDB::DateTime');
isa_ok($r->{md}, 'MojoX::MongoDB::DateTime');
is( $r->{dt}->epoch, $now, 'DateTime matches' );
is( $r->{md}->epoch, $now, 'MojoX::MongoDB::DateTime matches' );
$db->drop;

