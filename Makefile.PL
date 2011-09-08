use strict;
use warnings;
use lib 'ext';
use inc::Module::Install;

name 'MojoX-MongoDB';
abstract 'Mongo Driver for Perl Mojolicious';
perl_version '5.8.4';
author 'Florian Ragwitz <rafl@debian.org>';
author 'Kristina Chodorow <kristina@10gen.com>';
author 'minimalist <minimalist@lavabit.com>';
license 'Apache';
all_from 'lib/MojoX/MongoDB.pm';

requires 'Mojolicious';
requires 'Digest::MD5';
requires 'Tie::IxHash';
requires 'DateTime';
requires 'XSLoader';
requires 'boolean';
test_requires 'Test::Exception';
test_requires 'Tie::IxHash';
test_requires 'DateTime';
test_requires 'boolean';
test_requires 'Data::Types';
test_requires 'File::Slurp';
test_requires 'FileHandle';
test_requires 'JSON';
test_requires 'File::Temp' => '0.17';
test_requires 'Try::Tiny';

mongo;

no_index directory => 'ext';

repository 'git://github.com/naturalist/MojoX-MongoDB.git';


if ($Config::Config{useithreads}) {
    tests 't/*.t t/threads/*.t';
}

WriteAll;

package MY;
our $VERSION = '0.452';

use Config;

sub const_cccmd {
    my $inherited = shift->SUPER::const_cccmd(@_);
    return '' unless $inherited;

    if ($Config{cc} =~ /^cl\b/) {
        warn 'you are using MSVC... my condolences.';
        $inherited .= ' /Fo$@';
    }
    else {
        $inherited .= ' -o $@';
    }

    if ($Config{use64bitint}) {
        $inherited .= ' -DUSE_64_BIT_INT';
    }
    else {
        $inherited .= ' ';
    }

    return $inherited;
}
