#!/usr/bin/perl
use Test::More tests => 5;
use Chroniton::Backup;
use File::Copy qw(cp);

#
# test _compute_relative_path
#
# how to link /a/base/e/d to /a/base/c/d without absolute paths while in e
my $r = Chroniton::Backup::_compute_relative_path("/a/base/c/d", "/a/base/e/d"); # 1
is($r, "../c/d");
# ln -s ../c/d /a/b/e

# make sure the example in the comments works!
$r = Chroniton::Backup::_compute_relative_path("/foo/backup/old/bar/baz",
					       "/foo/backup/current/bar/baz"); # 2
is($r, "../../old/bar/baz");
# ln -s ../../old/bar/baz /foo/backup/current/bar/baz

# a longer example
$r = Chroniton::Backup::_compute_relative_path("/foo/backup/old/a/b/c/d/e/f/g/h/i/j",
					       "/foo/backup/new/k/l/m/n/o/p/q/r/s/j"); # 3
is($r, "../../../../../../../../../../old/a/b/c/d/e/f/g/h/i/j");

# some real examples

#
# test _compare_files
#

open(my $a, ">", "test.$$.a") or die "$!";
print {$a} "hello\n";
close $a;
cp "test.$$.a", "test.$$.b"; # make a identical to b

$r = Chroniton::Backup::_compare_files("test.$$.a", "test.$$.b");
is($r, 0, "copies should be identical");

sleep 2;

open($a, ">", "test.$$.a") or die "$!";
print {$a} "uh, oh... this file has been modified!\n";
close $a;

$r = Chroniton::Backup::_compare_files("test.$$.a", "test.$$.b");
is($r, 1, "non-identical files should not be identical");

END {
    # clean up
    eval {unlink "test.$$.a"};
    eval {unlink "test.$$.b"};
}
