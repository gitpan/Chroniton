#!/usr/bin/perl
# Copyright (c) 2006 Jonathan Rockway

use Test::More;
use Chroniton::Backup qw(backup clone_dir);
use Chroniton::Messages;
use Archive::Extract;
use File::Slurp;
my $root = "/tmp/test.$$";
my $archive = "t/clone_test_structure.tar";

#plan (skip_all => 'Set ALLTESTS=1 to do slow tests') if !$ENV{ALLTESTS};
die if !-e $archive;

open(STDERR, ">/dev/null"); # ignore irritating warnings from File::Copy.

# extract test hierarchy
mkdir "$root" or die;
mkdir "$root/src" or die;
mkdir "$root/dest" or die;
my $ae = Archive::Extract->new(archive=>$archive);
$ae->extract(to=>"$root/src");
my @files = @{$ae->files};
map {s{^[.]/}{}} @files;
@files = grep {-e "$root/src/$_" && !-d _} @files; # directories get tested automagically

# do some tests
plan(tests => (3*((scalar @files)*3 + 1)));
# because there are three tests (full, incremental, and another
# incremental) and each of these tests tests existence, file type, and
# contents.  each set of tests is begun by a test that the backup
# returned something, hence the + 1.

my $config = bless {}, 'Chroniton::Config'; # we never use this anyway
my $log    = Chroniton::Messages->new;#(\*STDOUT);

my $where = Chroniton::Backup::backup($config, $log, ["$root/src"], "$root/dest");
ok($where, "full backup");

foreach my $filename (@files){
    ok(-e "$where/$root/src/$filename", "$where/$root/src/$filename exists");
    ok(!-l "$where/$root/src/$filename", "$where/$root/src/$filename not a symlink");

    is_deeply([read_file("$where/$root/src/$filename")],
	      [read_file("$root/src/$filename")],
	      "contents of backup $where/$filename ".
	      "matches original $root/src/$filename");
}

for (1..2){
    $where = Chroniton::Backup::backup($config, $log, ["$root/src"],
				       "$root/dest",
				       "$where");
    ok($where, "incremental $_");
    foreach my $filename (@files){
	ok(-e "$where/$root/src/$filename", "$where/$root/src/$filename exists");
	ok(-l "$where/$root/src/$filename", "$where/$root/src/$filename is a symlink");
	is_deeply([read_file("$where/$root/src/$filename")],
		  [read_file("$root/src/$filename")],
		  "contents of backup $where/$filename ".
		  "matches original $root/src/$filename");
    }
}

END {
    eval {`rm -rf $root`}; # not portable
}
