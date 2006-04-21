#!/usr/bin/perl
# 11-full-backup.t 
# Copyright (c) 2006 Jonathan Rockway <jrockway@cpan.org>

use Test::More tests=>34;
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

backup();

sub backup {
    
    create($_) foreach (@files);
    symlink "$dir/src/foo", "$dir/src/foo_symlink";
    symlink "$dir/src", "$dir/src/dirlink";
    
    my $config = Test::MockObject->new;
    $config->set_always("destination", "$dir/dest");
    $config->set_always("locations", "$dir/src");
    $config->set_always("exclude", qr/^$/);
    $config->{time} = 1337;
    
    my $chroniton = Chroniton->new({config=>$config, interactive=>0});
    ok($chroniton, "created instance"); # 
    ok($chroniton->isa("Chroniton"), "right type"); # 
    my $contents = $chroniton->force_backup;
    ok($contents, "contents received"); # 
    ok($contents->isa("Chroniton::BackupContents")); # 
    my $where = $contents->location;
    ok(-e $where, "$where exists"); # 
    ok(-d $where, "and is a dir"); # 
    my @newfiles = map {"$where/$dir/$_"} @files;
    ok(-e $_, "$_ exists") for @newfiles; ###### 
    
    my $l = "$where/$dir/src/foo_symlink"; 
    ok(-l $l); #
    is(readlink($l), "$dir/src/foo", "link points to the right place");
    
    ### now verify the contents
    foreach (@files) { ######
	my $old = read_file("$dir/$_");
	my $new = read_file("$where/$dir/$_");
	is($old, $new, "$_ - original and copy match");
	my $file = ($contents->get_file("$dir/$_"))[0];
	ok($file->isa("Chroniton::File"), "$_ in backupset");
	is($file->metadata->{mtime},
	   (stat("$dir/$_"))[9], "mtime matches");
    }

    # deal with our very good friend the directory symlink
    ok(-l "$where/$dir/src/dirlink", "dirlink exists as a link");
    my $metadata = ($contents->get_file("$dir/src/dirlink"))[0]->metadata;
    like($metadata->{permissions}, qr/^l/, "link is a link");
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

