# $Id

use Test::More tests => 2;

use Test::File;

my $file = 'blib/script/webreaper';

print "bail out! Script file is missing!" unless file_exists_ok( $file );

my $output = `perl -c $file 2>&1`;

like( $output, qr/syntax OK$/, 'script compiles' );