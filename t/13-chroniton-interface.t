#!/usr/bin/perl
# 12-chroniton-interface.t 
# Copyright (c) 2006 Jonathan T. Rockway

use Test::More tests=>15;
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

# none of these work yet
eval {
    $where = $chroniton->force_archive;
};
like($@, qr/Not yet implemented/, "nyi, so error OK"); #13

eval {
    $where = $chroniton->restore("/foo");
};
like($@, qr/Not yet implemented/, "nyi, so error OK"); #14

eval {
    $where = $chroniton->restorable("/foo");
};
like($@, qr/Not yet implemented/, "nyi, so error OK"); #15

#print Dump($log);

END {
    eval {
	`rm -rf /tmp/test.$$`;
    };
}
