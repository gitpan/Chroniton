#!/usr/bin/perl
# Restore.pm
# Copyright (c) 2006 Jonathan Rockway

package Chroniton::Restore;
use strict;
use warnings;

use Chroniton::Event;
use Exporter;
use File::Copy qw(cp);
use File::Stat::ModeString;
use Time::HiRes qw(time);
use YAML qw(LoadFile);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(restore restorable);

=head1 NAME

Chroniton::Restore - implements restoration from backups

=head1 FUNCTIONS

In both of these functions, C<log> is the standard
L<Chronition::Messages|Chroniton::Messages> object.

=head2 restore(log, filename, from, [force])

Restores C<filename> (the original filename) from C<from>.  C<from> is
the path to the backup set containing C<filename>. Fails if C<filename> already
exists on the filesystem, unless C<force> is set. (DANGEROUS!)

Returns the number of files that were successfully restored.

=cut

my %CONTENTS_CACHE;

sub restore {
    my ($log, $filename, $from, $force) = @_;
    my $source = "$from/$filename";
    $log->debug($filename, "attempting to restore $source to $filename");
    $log->fatal("no file specified") if !$filename || !$from;

    # deal with error conditions
    $log->fatal("$filename already exists.  Move it out of the way or ".
		"specify 'force' (DANGEROUS)")
      if -e $filename && !$force;

    $log->fatal("cannot restore from $source from $from: file does not exist")
      if !-e $source;

    # if we don't have any metadata, that's bad... but do the restore anyway
    my $info = _get_file_data($log, $filename, $from) or
      $log->warning($filename, "couldn't look up file information in ".
		               "contents.yml");

    # do the restore, since it appears possible
    my $files_restored = 0;

    if(-d $source){
	$files_restored = _restore_directory($log, $source, $filename, $from);
    }
    else {
	$files_restored = _restore_file($log, $source, $filename,
					$info->{metadata});
    }

    return $files_restored;
}

sub _restore_directory {
    my ($log, $from, $to, $root) = @_;
    $log->debug($from, "restoring (d) $from to $to");
    
    my $files_restored = 0;
    
    # make the directory
    if(-d $from){
	my @subdirs = split m{/}, $to;
	my $d;
	my @errors;
	foreach(@subdirs){
	    $d .= "/$_";
	    mkdir $d or push @errors, $!;
	}
	if(!-d $to){
	    $log->error($to, "could not create $to: ". join(", ", @errors));
	    return;
	}
	else {
	    $log->add(Chroniton::Event->mkdir($to));
	}
    }

    # then restore to it recursively
    opendir my $dh, $from or $log->error($from, "couldn't inspect $from");
    foreach my $entry (readdir $dh){
	next if $entry eq '..' || $entry eq '.';
	my $source = "$from/$entry";
	my $dest   = "$to/$entry";
	
	if(!-d $source){
	    my $entry_ref = _get_file_data($log, $dest, $root);
	    $files_restored += _restore_file($log, $source, $dest, $entry_ref->{metadata});
	}
	else {
	    # recurse!
	    $files_restored += _restore_directory($log, $source, $dest, $root);
	}
    }   

    # and finally set the attributes on it
    my $metadata = _get_file_data($log, $to, $root)->{metadata};
    _restore_metadata($log, $to, $metadata);

    return $files_restored;
}

sub _restore_file {
    my ($log, $from, $to, $metadata_ref) = @_;
    $log->debug($from, "restoring $from to $to");
    
    # dereference symlinks
    my $max_levels = 100;
    my $original = $from;
    while ($max_levels-- && -l $from){
	$from = readlink $from;
    }
    
    # if it's still a link, fail.
    if(-l $from){
	$log->error($original, "too many levels of symbolic links");
	return 0;
    }

    my $status = 1;
    $status = unlink $to if-e $to; # TFM said restoring to an existing file would kill it, it's not lying.
    $log->warning($to, "existing destination $to could not be unlinked, data may not be restored!") if !$status;
    
    my $time = time();
    $status = cp($from, $to);
    if(!-e $to || !$status){
	$log->error($to, "could not restore $from to $to: $!");
	return 0;
    }
    else {
	my $size = (stat $to)[7];
	$log->add(Chroniton::Event->copy($from, $to, time() - $time, $size));
    }
    
    # restore metadata
    _restore_metadata($log, $to, $metadata_ref);

    # TODO: extended filesystem attributes.
    return 1;
}

sub _restore_metadata {
    my ($log, $to, $metadata_ref) = @_;
    
    my $mtime = $metadata_ref->{mtime} || undef; 
    my $atime = $metadata_ref->{atime} || undef;

    utime $atime, $mtime, $to # set to time() if atime and mtime weren't in the metadata list
      or $log->warning($to, "could not set access or modification times on $to: $!");
    
    my $permissions = $metadata_ref->{permissions} || "-rw-r--r--"; # use a sane default
    my $n_permissions = string_to_mode($permissions);
    chmod $n_permissions, $to 
      or $log->warning($to, "couldn't set permissions $permissions on $to");
    
    my $user  = $metadata_ref->{uid};
    my $uid   = getpwnam($user) || -1;
    my $group = $metadata_ref->{gid};
    my $gid = getgrnam($group) || -1;

    chown $uid, $gid, $to
      or $log->warning($to, "couldn't set ownership $uid:$gid ($user:$group) on $to");
    return;
}

=head2 restorable(log, filename, from, [fuzzy])

Lists all files under directory C<from> that are versions of
C<filename>.  Examines the C<contents.yml> under each subdirectory of
C<from>, looking for C<filename>.  If fuzzy is true, looks for
similarly named files.  (TODO: implement this.)

Returns a list of references, where each reference is:

     [location_of_backupset, modification_date, permissions, size, user, group]
      0                      1                  2            3     4     5
C<location_of_backup> is where the backup is located, and
C<modification_date> is the date when the file was last modified.

=cut

sub restorable {
    my ($log, $filename, $from, $fuzzy) = @_;
    my @results;
    
    $log->debug($from, "examining $from for versions of $filename");
    opendir(my $dh, $from) or $log->fatal("cannot inspect $from: $!");
    foreach my $subdir (readdir $dh){
	next if $subdir eq '.' || $subdir eq '..';
	my $subdir = "$from/$subdir";
	next if !-d $subdir;
	
	$log->message($subdir, "looking for contents.yml in $subdir");
	my $data = _get_file_data($log, $filename, $subdir, $fuzzy);
	
	$log->debug("$subdir/contents.yml", "found $filename in $subdir") if $data;
	push @results, [$subdir,
			$data->{metadata}->{mtime},
			$data->{metadata}->{permissions},
			$data->{metadata}->{size},
			$data->{metadata}->{uid},
			$data->{metadata}->{gid},
		       ] if $data;
	
    }
    # FIXME: use some standard function to filter this, mtime might not
    # be the key for much longer
    {
	my %seen;
	@results = grep {$seen{$_->[0]}++ == 0} @results;
    }
    return sort {$a->[1] <=> $b->[1]} @results;
}

sub _get_file_data {
    my ($log, $filename, $from) = @_;
    eval {
	$CONTENTS_CACHE{$from} = LoadFile("$from/contents.yml")
	  if !exists $CONTENTS_CACHE{$from};
    };
    if($@){
	$log->warning($from, "$from may be a corrupt backup! ($@)");
	return;
    }
    my %files = %{$CONTENTS_CACHE{$from}};
    return $files{$filename};
}

1;
