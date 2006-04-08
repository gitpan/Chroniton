#!/usr/bin/perl
# 13-restore.t
# Copyright (c) 2006 Jonathan T. Rockway

use Test::More tests=>2;
use Chroniton::Restore qw(restore restorable);
use Chroniton::Messages;

# the actual test is done in #20... this tests failure in 
# some boundary cases

my $log = Chroniton::Messages->new;

eval {
    restore($log, "/tmp/foo", undef);
};
ok($@, "failed when given bad data");

eval {
    restore($log, undef, "/tmp/foo");
};
ok($@, "failed when given bad data");

## TODO: more tests.
