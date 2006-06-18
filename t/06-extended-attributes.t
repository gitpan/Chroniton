#!/usr/bin/perl
# 06-extended-attributes.t 
# Copyright (c) 2006 Jonathan Rockway <jrockway@cpan.org>

use Test::More;
use strict;
use warnings;

use Chroniton;
use Chroniton::Messages;
use Test::MockObject;

BEGIN {
    eval {
	require File::ExtAttr;
    };
    if($@){
	plan skip_all => 
	  "File::ExtAttr doesn't work, skipping attribute tests";
	exit 0;
    }
    else {
	plan tests => 11;
    }
}

use File::ExtAttr qw(setfattr getfattr);

mkdir "/tmp/test.$$";
mkdir "/tmp/test.$$/src";
mkdir "/tmp/test.$$/dest";
`touch /tmp/test.$$/src/file`;

# 1
ok(-e "/tmp/test.$$/src/file");

# 2..4
ok(setfattr("/tmp/test.$$/src/file", "user.foo", "foo"));
ok(setfattr("/tmp/test.$$/src/file", "user.bar", "bar"));
ok(setfattr("/tmp/test.$$/src/file", "user.baz", "baz"));

my $log = Chroniton::Messages->new;
my $config = Test::MockObject->new;

$config->set_always("destination", "/tmp/test.$$/dest");
$config->set_always("archive_after", "1337");
$config->set_always("locations", "/tmp/test.$$/src");
$config->set_always("exclude", []);
$config->{time} = time();

my $chroniton = Chroniton->new({verbose	     => 0,
				interactive  => 0,
				log	     => $log,
				config	     => $config});


my $contents = $chroniton->backup;

# 5
ok($contents);

unlink "/tmp/test.$$/src/file";
ok(!-e "/tmp/test.$$/src/file"); #6

my $file = ($chroniton->restorable("/tmp/test.$$/src/file"))[0];
ok($file); #7
$chroniton->restore($file);

ok(-e "/tmp/test.$$/src/file"); #8

# 9..11
ok(getfattr("/tmp/test.$$/src/file", "user.foo"). "foo");
ok(getfattr("/tmp/test.$$/src/file", "user.bar"). "bar");
ok(getfattr("/tmp/test.$$/src/file", "user.baz"). "baz");


END {
    eval {
	`rm -rf /tmp/test.$$`;
    };
}



