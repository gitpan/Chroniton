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
use Digest::MD5;

use Chroniton::Messages;
use Chroniton::Message;
use Chroniton::Event;
use Chroniton::Config;
use Chroniton::BackupContents;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(backup);

=head1 NAME

Chroniton::Backup - implements full and incremental backups

=head1 EXPORT

None of these subroutines are exported by default.  Please load them
into your namespace by specifying them on the module load line:

    use Chroniton::Backup qw(backup);

=head2 backup($config, $log, \@sources, $destination, [$against])

Perfoms a backup of each file in @sources to a new subdirectory of
$destination.  If $against is specified, an incremental backup is
performed by comparing the files in each of @sources to the
identically named files in $against.  If the files are the same, the new
file in $destination is linked to the version in $against (instead of being 
copied from the $source).

Returns a BackupSet object.  Dies on a fatal error, otherwise logs
errors and warnings to $log, a C<Chroniton::Messages> object.

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
    my $date = $config->{time};
    my $storage_dir = "$destination/backup_$date";
    if(-e $storage_dir){
	# if you have more than one backup in one second, the second backup
	# will fail unless we make the dates unique
	$storage_dir .= time();
    }
    mkdir $storage_dir or 
      $log->fatal("cannot create storage directory: $!", $storage_dir);
    my $contents = Chroniton::BackupContents->new($storage_dir);
    
    # back up each source
    foreach my $src (@sources){
	if(!-e $src){
	    $log->error($src, "can't backup $src because it doesn't exist");
	    next;
	}

	my $dest = "$storage_dir/$src";
	my $this_against = "$against/$src" if $against;
	my @dirs = split m{/}, $src;
	my $adir = shift @dirs;
	unshift @dirs, $adir if $adir ne "/";
	
	# make original parent directories in the backup dir
	my $dir = $storage_dir;
	foreach(@dirs){
	    $dir .= "/$_";
	    mkdir $dir;
	    $log->add(Chroniton::Event->mkdir($dir))      if  -d $dir;
	    $log->fatal("couldn't create $dir: $!", $dir) if  !-e $dir;
	}
	$contents->add($src);
	# do it!
	_clone_dir($config, $log, $contents, $src, $dest, $this_against, 
		   \&_compare_files);
    }

    $log->message($sources, "$mode backup of $sources completed");
    return $contents;
}

=head2 _clone_dir($config, $log, $contents, $src, $dest, [$against, $compare_ref])

Clones $src into $dest, recursively decending into subdirectories,
depth first.  If $against is specified, each file in $src is compared
against the file of the same name in $against via the $compare_ref
subroutine.  This routine should return 1 if the file from $src needs
to be copied to $dest, or 0 if the file placed in $dest should be a
(relative) symbolic link to the file in $against.

Returns nothing.  Dies on a fatal error, otherwise logs errors and
warnings to $log, a C<Chroniton::Messages> object.

=cut

sub _clone_dir {
    my ($config, $log, $contents, $src, $dest, $against, $compare_ref) = @_;

    my $mode = ($against) ? "incremental" : "full";
    $log->debug($src, "cloning $src to $dest (mode: $mode)".
		(($against) ? " against $against" : "")); 

    if($mode eq "incremental" && !-d $against){
	$log->message($against, "increment dir $against does not exist");
	undef $against; # do a full backup in this case
    }
    
    my $status = opendir(my $dir, $src);
    if(!$status){
	$log->error($src, "couldn't open $src for inspection");
	return;
    }
    
        
    # TODO: what happens when readdir fails midway thru?
    my @files = readdir $dir; 
    my @exclude_list = $config->exclude;
    @files = _filter_filelist($log, $src, [@files], [@exclude_list]);
    
    foreach my $file (@files){
	
	my $src_file      = "$src/$file";
	my $dest_file     = "$dest/$file";
	my $against_file  = "$against/$file" if $against;
	my $original;
	
	next if $file eq '.' || $file eq '..';
	
	if(-d $src_file && !-l $src_file){
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
		_clone_dir($config, $log, $contents, $src_file, $d,
			   $against_file, $compare_ref);
	    }
	}
	else {
	    # it's a regular file, so decide whether to copy or link

	    my $what_to_do = 1; # copy by default
	    if($against && !-l $src_file){ 
		$what_to_do = eval { &$compare_ref($src_file, $against_file);};
		if($@){
		    $log->error($src_file, "could not compare $src_file ".
				           "and $against_file: $@");
		    $what_to_do = 1;
		}
	    }
	    

	    # decision has been made, act on it.
	    if(-l $src_file || $what_to_do == 1){
		my $error;
		my $start = time(); # provide timing information
		if(-l $src_file){
		    # if original file is a link, make the backup one, too
		    my $target = readlink($src_file);
		    symlink $target, $dest_file or $error = $!;
		}
		else {
		    cp($src_file, $dest_file) or $error = $!;
		}
		my $end = time();
		
		# so user can't write to these files without trying
		chmod 0400, $dest_file unless -l $src_file; 
		
		if($error){
		    $log->error($src_file,
				"couldn't copy $src_file to $dest_file: $!");
		    next;
		    
		}
		else {
		    my $bytes;
		    if(-l $src_file) {
			$bytes = (lstat $dest_file)[7];
		    }
		    else {
			$bytes = (stat $dest_file)[7];
		    }
		    $log->add(Chroniton::Event->copy($src_file,
						     $dest_file,
						     $end-$start,
						     $bytes));
		}
	    }
	    
	    else { # link
		my $from = _compute_relative_path($against_file, $dest_file);
		$original = $from;
		my $status = symlink $from, $dest_file;
		if($status){
		    $log->add(Chroniton::Event->link($against_file,
						     $dest_file));
		}
		else {
		    $log->error($against_file,
				"couldn't link $against_file to $dest_file ".
				"(source $src_file, mapping: $from)");
		    next;
		}
	    } # end link
	} # end dir/not dir if

	# make an entry in the file list, since this file backed up OK
	eval {
	    if($original){
		$original =~ s{^/?(?:[.][.]/)+}{}g; # strip leading ../../
	    }
	    $contents->add($src_file, $original);
	};
	if($@){
	    $log->error($src_file, "problem storing file metadata");
	}
	
    } # end readdir
    closedir $dir;
}

sub _filter_filelist {
    my ($log, $prefix, $files_ref, $filter_ref) = @_;
    my @okay_files;
  FILE: foreach my $file (@$files_ref){
	my $path = "$prefix/$file";
      FILTER: foreach my $filter (@$filter_ref){
	    if($path =~ $filter){
		$log->debug($path, "skipping $path due to exclude rules");
		next FILE;
	    }
	}
	push @okay_files, $file;
    }
    return @okay_files;
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
    return 1 if !-e $b; # copy if there's nothing to diff against
    
    my $md_a = Digest::MD5->new;
    my $md_b = Digest::MD5->new;
    
    open my $afh, "<", $a or die "could not open $a: $!";
    open my $bfh, "<", $b or die "could not open $b: $!";
    
    $md_a->addfile($afh);
    $md_b->addfile($bfh);

    return ($md_a->hexdigest ne $md_b->hexdigest) ? "1" : "0";
    
    #confess "a $a does not exist" if !-e $a; # this shouldn't happen!!
    #
    #my $ma = (stat $a)[9];
    #my $mb = (stat $b)[9];
    #return ($ma > $mb) ? 1 : 0;
}

1;
