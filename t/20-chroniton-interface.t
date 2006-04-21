#!/usr/bin/perl
# 12-chroniton-interface.t 
# Copyright (c) 2006 Jonathan T. Rockway

use Test::More tests=>27;
use Test::MockObject;
use Time::HiRes;
use Chroniton;
use Chroniton::Messages;
use File::Stat::ModeString;
use YAML qw(Dump);
use strict;
use warnings;

my $log = Chroniton::Messages->new;
my $config = Test::MockObject->new();
mkdir "/tmp/test.$$";
die if !-w "/tmp/test.$$";
mkdir "/tmp/test.$$/src";
mkdir "/tmp/test.$$/dest";
mkdir "/tmp/test.$$/src/dir";
`touch /tmp/test.$$/src/dir/dirfoo`;
`touch /tmp/test.$$/src/foo`;
`touch /tmp/test.$$/src/bar`;

diag("working in /tmp/test.$$");

$config->set_always("destination", "/tmp/test.$$/dest");
$config->set_always("archive_after", "7");
$config->set_always("locations", "/tmp/test.$$/src"); # is this portable?
$config->set_always("exclude", []);

$config->{time} = time();

my $chroniton = Chroniton->new({verbose	     => 0,
				interactive  => 0,
				log	     => $log,
				config	     => $config});

my $where;
my $contents;
eval {
    $contents = $chroniton->backup;
    $where = $contents->location;
    print $chroniton->summary;
};
ok(!$@, "no errors"); #1
ok(-e $where, "backup exists"); #2 ## backup is tested more fully elsewhere
ok(-r "$where/../state.yml", "state exists"); #3

# try it again

undef $where;
undef $chroniton;

$chroniton = Chroniton->new({verbose	  => 0,
			     interactive  => 0,
			     log	  => $log,
			     config	  => $config});

eval {
    $contents = $chroniton->backup;
    $where = $contents->location;

    print $chroniton->summary;
};
ok(!$@, "no errors"); #4
ok(-e $where, "backup exists"); #5
ok(-r "$where/../state.yml", "state exists"); #6

# force full this time
undef $where;
undef $chroniton;

$chroniton = Chroniton->new({verbose	  => 0,
			     interactive  => 0,
			     log	  => $log,
			     config	  => $config});

eval {
    $contents = $chroniton->force_backup;
    $where = $contents->location;

    print $chroniton->summary;
};
ok(!$@, "no errors"); #7
ok(-e $where, "backup exists"); #8
ok(-r "$where/../state.yml", "state exists"); #9

# force incremental this time
`touch /tmp/test.$$/src/dir/dirfoo`; # so that something changes
undef $chroniton;
$chroniton = Chroniton->new({verbose	  => 0,
			     interactive  => 0,
			     log	  => $log,
			     config	  => $config});

eval {
    $contents = $chroniton->force_incremental();
    $where = $contents->location;

    print $chroniton->summary;
};
ok(!$@, "no errors"); #10
ok(-e $where, "backup exists"); #11
ok(-r "$where/../state.yml", "state exists"); #12

my @files;
eval {
    @files = $chroniton->restorable("/tmp/test.$$/src/dir");
};
ok(scalar @files, "/dir/* is restorable");

unlink "/tmp/test.$$/src/dir/dirfoo";
rmdir "/tmp/test.$$/src/dir";
ok(!-e "/tmp/test.$$/src/dir", "dir was removed"); 
ok(!-e "/tmp/test.$$/src/dir/dirfoo", "dir/dirfoo was removed");
eval {
    $chroniton->restore($files[0]);
};
ok(-e "/tmp/test.$$/src/dir", "dir was restored");
ok(-e "/tmp/test.$$/src/dir/dirfoo", "dir/dirfoo was restored");

eval {
    @files = $chroniton->restorable("/tmp/test.$$/src/foo");
};
ok(scalar @files, "/foo is restorable");

unlink "/tmp/test.$$/src/foo";
ok(!-e "/tmp/test.$$/src/foo", "got rid of the original copy of foo");
eval {
    $chroniton->restore($files[0]);
};
ok(-e "/tmp/test.$$/src/foo", "restored /foo");

# now try a forced restore
my $count;
eval {
    $count = $chroniton->restore($files[0], 0);
};
is($count, undef, "restore should fail if not forced");

eval {
    $count = $chroniton->restore($files[0], 1);
};
is($count, 1, "restore should succeed if forced");

# archive everything, and try the restores again
undef $where;
eval {
    $where = $chroniton->force_archive;    
};
ok(!$@, "no errors");
ok(-e $where, "archive exists (in $where)");
print $chroniton->summary;

undef @files;
eval {
    @files = $chroniton->restorable("/tmp/test.$$/src/foo");
};

ok(@files, "dir is still restorable");

$files[0]->metadata->{permissions} = "-r--r--r-x";

undef $count;
eval {
    $count = $chroniton->restore($files[0], 1);
};
is($count, 1, "restore should succeed after archive");
is((stat "/tmp/test.$$/src/foo")[2], string_to_mode("-r--r--r-x"), "permissions stuck");
print $chroniton->summary;

END {
    eval {
	`rm -rf /tmp/test.$$`;
    };
}
