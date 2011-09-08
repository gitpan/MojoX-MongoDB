use strict;
use warnings;

use Test::More tests => 9;

use MojoX::MongoDB;
use MojoX::MongoDB::DateTime;
use DateTime;

my $now = time;
my $d1 = MojoX::MongoDB::DateTime->from_epoch( epoch => $now );
my $d2 = MojoX::MongoDB::DateTime->from_epoch( epoch => $now - 3600 );
isa_ok($d1, 'MojoX::MongoDB::DateTime');
ok( $d1 > $d2, 'overload works on comparisons' );
is( $d1 - $d2, 3600, 'ovreload works on aritmetic ops' );
is( "$d1", "$now", 'overload works on strings' );

my $conn = MojoX::MongoDB::Connection->new();
my $db = $conn->get_database('foo');
my $c = $db->get_collection('bar');

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

