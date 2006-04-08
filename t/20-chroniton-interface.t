#!/usr/bin/perl
# 12-chroniton-interface.t 
# Copyright (c) 2006 Jonathan T. Rockway

use Test::More tests=>23;
use Test::MockObject;
use Time::HiRes;
use Chroniton;
use Chroniton::Messages;
use YAML qw(Dump);

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


$config->set_always("destination", "/tmp/test.$$/dest");
$config->set_always("archive_after", "7");
$config->set_always("locations", "/tmp/test.$$/src"); # is this portable?
$config->{time} = time();

my $chroniton = Chroniton->new({verbose	     => 0,
				interactive  => 0,
				log	     => $log,
				config	     => $config});

my $where;
eval {
    $where = $chroniton->backup;
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
    $where = $chroniton->backup;
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
    $where = $chroniton->force_backup;
    print $chroniton->summary;
};
ok(!$@, "no errors"); #7
ok(-e $where, "backup exists"); #8
ok(-r "$where/../state.yml", "state exists"); #9


# force incremental this time
`touch /tmp/test.$$/src/dir/dirfoo`; # so that something changes
undef $chroniton;
undef $where;
$chroniton = Chroniton->new({verbose	  => 0,
			     interactive  => 0,
			     log	  => $log,
			     config	  => $config});

eval {
    $where = $chroniton->force_incremental;
    print $chroniton->summary;
};
ok(!$@, "no errors"); #10
ok(-e $where, "backup exists"); #11
ok(-r "$where/../state.yml", "state exists"); #12

eval {
    $where = $chroniton->force_archive;
};
like($@, qr/Not yet implemented/, "nyi, so error OK"); #13

my @files;

eval {
    @files = $chroniton->restorable("/tmp/test.$$/src/dir");
};
ok(scalar @files, "/dir/* is restorable"); #14

unlink "/tmp/test.$$/src/dir/dirfoo";
rmdir "/tmp/test.$$/src/dir";
ok(!-e "/tmp/test.$$/src/dir", "dir was removed"); # 15
ok(!-e "/tmp/test.$$/src/dir/dirfoo", "dir/dirfoo was removed"); # 16
eval {
    $chroniton->restore("/tmp/test.$$/src/dir", $files[0]->[0]);
};
ok(-e "/tmp/test.$$/src/dir", "dir was restored"); # 17
ok(-e "/tmp/test.$$/src/dir/dirfoo", "dir/dirfoo was restored"); # 18

eval {
    @files = $chroniton->restorable("/tmp/test.$$/src/foo");
};
ok(scalar @files, "/foo is restorable"); # 19

unlink "/tmp/test.$$/src/foo";
ok(!-e "/tmp/test.$$/src/foo", "got rid of the original copy of foo"); #20
eval {
    $chroniton->restore("/tmp/test.$$/src/foo", $files[0]->[0]);
};
ok(-e "/tmp/test.$$/src/foo", "restored /foo"); #21

# now try a forced restore
my $count;
eval {
    $count = $chroniton->restore("/tmp/test.$$/src/foo", $files[0]->[0], 0);
};
is($count, undef, "restore should fail if not forced"); # 22

eval {
    $count = $chroniton->restore("/tmp/test.$$/src/foo", $files[0]->[0], 1);
};
is($count, 1, "restore should succeed if forced"); #23

#print Dump($log);

END {
    eval {
	`rm -rf /tmp/test.$$`;
    };
}
