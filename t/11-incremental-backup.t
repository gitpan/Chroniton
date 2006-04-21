#!/usr/bin/perl
# 11-incremental-backup.t 
# Copyright (c) 2006 Jonathan Rockway <jrockway@cpan.org>

use Test::More tests=>15;
use Chroniton;
use File::Temp qw(tempdir);
use Test::MockObject;
use File::Slurp;
use strict;
use warnings;

my $dir = tempdir(CLEANUP => 1);
#diag("storing to $dir");

my @files = qw(src/foo src/bar src/baz/.foo src/baz/foo
	       src/bat/foo src/.bat/.foo);
create($_) foreach (@files);

my $config = Test::MockObject->new;
$config->set_always("destination", "$dir/dest");
$config->set_always("locations", "$dir/src");
$config->set_always("exclude", qr/^$/);
$config->{time} = 1337;

my $chroniton = Chroniton->new({config=>$config, interactive=>0});
ok($chroniton, "created instance"); # 
ok($chroniton->isa("Chroniton"), "right type"); # 
my $contents = $chroniton->force_backup;
ok($contents); #
is_deeply([sort grep {!-d $_} $contents->ls], [sort map {"$dir/$_"} @files],
	  "files were backed up properly");

my $old = read_file("$dir/src/foo");
open(my $foo, ">$dir/src/foo") or die;
print {$foo} "I messed up the contents!  Oh no!";
close $foo;
is(read_file("$dir/src/foo"), "I messed up the contents!  Oh no!");

my $where = $contents->location;
undef $contents;
$contents = $chroniton->force_incremental($where);
ok($contents);
$where = $contents->location;

my $file  = $contents->get_file("$dir/src/foo");
ok(!-l "$where/$dir/src/foo", "file was copied, not linked");
isnt($old, read_file("$where/$dir/src/foo"), "new file is right");

undef $contents;
$contents = $chroniton->force_incremental($where);
$where = $contents->location;
my @bfiles = $contents->ls;
ok(@bfiles, "got some files");
ok(-l "$where/$dir/$_", "$_ is a link") for (@files);

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
