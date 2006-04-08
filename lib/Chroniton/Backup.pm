#!/usr/bin/perl
# Backup.pm - [description]
# Copyright (c) 2006 Jonathan T. Rockway
# $Id: $

package Chroniton::Backup;
use strict;
use warnings;
use Carp;

use Exporter;
use File::Copy qw(cp);
use File::Spec::Functions qw(abs2rel catfile splitpath catfile);
use Time::HiRes qw(time);
use DateTime;
#use Digest::SHA1; 

use Chroniton::Messages;
use Chroniton::Message;
use Chroniton::Event;
use Chroniton::Event::FileInSet;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(backup clone_dir);

=head1 NAME

Chroniton::Backups - implements full and incremental backups

=head1 EXPORT

None of these subroutines are exported by default.  Please load them
into your namespace by specifying them on the module load line:

    use Chroniton::Backup qw(backup clone_dir);

=head2 backup($config, $log, \@sources, $destination, [$against])

Perfoms a backup of each file in @sources to a new subdirectory of
$destination.  If $against is specified, an incremental backup is
performed by comparing the files in each of @sources to the
identically named files in $against.  If the files are the same, the new
file in $destination is linked to the version in $against (instead of being 
copied from the $source).

Returns the path of the newly created storage directory.  Dies on a
fatal error, otherwise logs errors and warnings to $log, a
C<Chroniton::Messages> object.

=cut

sub backup {
    my ($config, $log, $sources_ref, $destination, $against) = @_;
    my @sources = @{$sources_ref};
    
    my $mode = ($against) ? "incremental" : "full";
    my $sources = join(', ', @sources);
    $log->message($sources, "starting $mode backup of $sources to $destination");

    # create the destination directory
    mkdir $destination if !-e $destination;
    $log->fatal("cannot write to destination directory ($!)", $destination)
      if !-d $destination || !-w _;
    
    # if it didn't fail, log the creation event
    $log->add(Chroniton::Event->mkdir($destination));

    # create the storage directory
    my $date = DateTime->now;
    $date =~ s/\s//g; # whitespace in filenames is unnecessary

    my $storage_dir = "$destination/backup_$date";
    if(-e $storage_dir){
	# if you have more than one backup in one second, the second backup
	# will fail unless we make the dates unique
	$storage_dir .= time();
    }
    mkdir $storage_dir or 
      $log->fatal("cannot create storage directory: $!", $storage_dir);
    
    # back up each source
    foreach my $src (@sources){
	my $dest = "$storage_dir/$src";
	my $this_against = "$against/$src" if $against;
	my @dirs = split m{/}, $src;
	
	# make original parent directories in the backup dir
	my $dir = $storage_dir;
	foreach(@dirs){
	    $dir .= "/$_";
	    mkdir $dir;
	    $log->add(Chroniton::Event->mkdir($dir))      if  -d $dir;
	    $log->fatal("couldn't create $dir: $!", $dir) if !-d $dir;
	}
	
	# do it!
	clone_dir($config, $log, $src, $dest, $this_against, \&_compare_files);
    }

    $log->message($sources, "$mode backup of $sources completed");
    return $storage_dir;
}

=head2 clone_dir($config, $log, $src, $dest, [$against, $compare_ref])

Clones $src into $dest, recursively decending into subdirectories,
depth first.  If $against is specified, each file in $src is compared
against the file of the same name in $against via the $compare_ref
subroutine.  This routine should return 1 if the file from $src needs
to be copied to $dest, or 0 if the file placed in $dest should be a
(relative) symbolic link to the file in $against.

Returns nothing.  Dies on a fatal error, otherwise logs errors and
warnings to $log, a C<Chroniton::Messages> object.

=cut

sub clone_dir {
    my ($config, $log, $src, $dest, $against, $compare_ref) = @_;

    my $mode = ($against) ? "incremental" : "full";
    $log->debug($src, "cloning $src to $dest (mode: $mode)".
		(($against) ? " against $against" : "")); 

    if($mode eq "incremental" && !-d $against){
	$log->warning($against, "increment dir $against does not exist");
    }
    
    my $status = opendir(my $dir, $src);
    if(!$status){
	$log->error($src, "couldn't open $src for inspection");
	return;
    }
    
        
    # TODO: what happens when readdir fails midway thru?
    #while(my $file = readdir $dir){
    my @files = readdir $dir; # benchmark indicates that this is 34% faster
    foreach my $file (@files){
	
	my $src_file      = "$src/$file";
	my $dest_file     = "$dest/$file";
	my $against_file  = "$against/$file" if $against;
	
	next if $file eq '.' || $file eq '..';
	next if -l $src_file && -d _; # skip directory symlinks

	if(-d $src_file){
	    my $d = $dest_file; # short alias to save typing :)

	    mkdir $d;
	    if(!-d $d){
		$log->error($d, "couldn't create $d: $!");
		# skip to next file
		next; # not really needed
	    }
	    else {
		$log->add(Chroniton::Event->mkdir($d)) if -d $d;
		
		# recurse
		clone_dir($config, $log, $src_file, $d, $against_file, $compare_ref);
	    }
	}

	else {
	    # it's a regular file
	    # decide whether to copy or link
	    my $what_to_do = 1; # copy by default
	    if($against){ # if in incremental mode
		$what_to_do = eval { &$compare_ref($src_file, $against_file);};
		if($@){
		    $log->error($src_file,
				"could not compare $src_file and $against_file: $@");
		    $what_to_do = 1;
		}
	    }
	    
	    if($what_to_do == 1){ # copy
		my $error;
		my $start = time(); # provide timing information
		cp($src_file, $dest_file) or $error = $!;
		my $end   = time();
		
		# so user can't write to these files without trying
		# TODO: save permissions somewhere, so we can restore them.
		chmod 0400, $dest_file; 
		
		if($error){
		    $log->error($src_file,
				"couldn't copy $src_file to $dest_file: $!");
		    next;
		    
		}
		else {
		    $log->add(Chroniton::Event->copy($src_file,
						     $dest_file,
						     $end-$start,
						     (stat $dest_file)[7]));
		}
	    }
	    
	    else { # link
		my $from = _compute_relative_path($against_file, $dest_file);
		$log->debug($src_file, "$against_file -> ($from) -> $dest_file");
		my $status = symlink $from, $dest_file;
		if($status){
		    $log->add(Chroniton::Event->link($against_file,
						     $dest_file));
		}
		else {
		    $log->add($against_file,
			      "couldn't link $against_file to $dest_file ".
			      "(source $src_file, mapping: $from)");
		    next;
		}
	    } # end link
	} # end dir/not dir if

	# make an entry in the file list, since this file backed up OK
	$log->add(Chroniton::Event::FileInSet->new($src_file, $dest_file));
	
    } # end readdir
    closedir $dir;
}

# computes a path suitable for relative links.
#
# imagine that you are in directory /foo/backup/current/bar and you want to
# create a link "baz" to the file in /foo/backup/old/bar/baz.  This function will
# return the correct first argument to symlink ("../../old/bar/baz" in this case).
sub _compute_relative_path {
    my $original    = shift; # what we're linking to
    my $destination = shift; # file name that the link will have
    
    # clean up destination to conform to abs2rel's expectation. namely that the file-
    # name is not specified already.
    my @dest = splitpath($destination);
    pop @dest;
    
    return abs2rel($original, catfile(@dest));
}

# arguments: 
# a: "original" file
# b: file that we're incrementing against

# not an argument, but c is the file that will be in the new backup set, 
# whether it's a link or a copy is based on the output of this function

# returns:
# 1 if a should be copied into the new direcory, creating "c"
# 0 if b should be linked into the new direcory, creating "c"
sub _compare_files {
    my $a = shift;
    my $b = shift;
    
    # TODO: i'd really like to use checksums, but they're too f*#&ing slow.
    # ex: /Users/jon/Library (full backup, 558 seconds, 891MiB )
    #                        (incremental, 879 seconds,  22MiB )
    # OUCH. OUCH. OUCH.
    
    #my $sha_a = Digest::SHA1->new;
    #my $sha_b = Digest::SHA1->new;
    #
    #open my $afh, "<", $a or die "could not open $a: $!";
    #open my $bfh, "<", $b or die "could not open $b: $!";
    #
    #$sha_a->addfile($afh);
    #$sha_b->addfile($bfh);

    #return $sha_a->hexdigest ne $sha_b->hexdigest;

    return 1 if !-e $b; # copy if there's nothing to diff against
    confess "a $a does not exist" if !-e $a; # this shouldn't happen!!

    my $ma = (stat $a)[9];
    my $mb = (stat $b)[9];
    return ($ma > $mb) ? 1 : 0;
}

1;
