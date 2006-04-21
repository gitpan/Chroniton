#!/usr/bin/perl
# 11-exclude-list.t - test exclude list during backups
# Copyright (c) 2006 Jonathan Rockway

use Test::More;
use Test::MockObject;
use Chroniton::Backup qw(backup);
use File::Temp qw(tempdir);

use Chroniton::Messages;
my $dir = tempdir(CLEANUP => 1);

my $log = Chroniton::Messages->new(\*STDOUT);
my $config = Test::MockObject->new();
$config->set_always("destination", "$dir/dest");
$config->set_always("locations", "$dir/src"); # is this portable?
$config->set_list("exclude", (qr{/ba}, qr{/nothing}));

my @files = qw(src/foo src/bar src/baz src/afoo/bar src/aba/abc src/aba/bar
	       src/aba/abar src/.nothing src/nothing/foo src/nothing/bar
	       src/abar/bar/a src/.bar/bar src/.bar/foo);

plan tests=> 1+2*scalar @files;
create($_) for @files;

ok(-e "$dir/$_", "$_ created") for(@files);

my $contents = backup($config, $log, ["$dir/src"], "$dir/dest");
my $where = $contents->location;

ok(-d $where, "$where exists");
foreach(@files){
    my $file = "$dir/$_";
    my $m = $file =~ qr{/ba} || $file =~ qr{/nothing};
    if($m){
	ok(!-e "$where/$file", "$file shouldnt be backed up");
    }
    else {
	ok(-e "$where/$file", "$file should be backed up");
    }
}


sub create {
    my $name = shift;
    my @dirs = split m{/}, $name;
    pop @dirs;
    
    my $dirs = "$dir/";
    foreach(@dirs){
	$dirs .= "/$_";
	mkdir $dirs;
    }
    
    open(my $fh, ">", "$dir/$name") or die "cant create $name ($!)";
    print {$fh} $name;
    close $fh;
}
