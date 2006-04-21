#!/usr/bin/perl
# Restore.pm
# Copyright (c) 2006 Jonathan Rockway

package Chroniton::Restore;
use strict;
use warnings;

use Archive::Extract;
use Chroniton::Event;
use File::Copy qw(cp);
use File::Stat::ModeString;
use Time::HiRes qw(time);
use YAML::Syck qw(LoadFile);
use File::Temp qw(tempdir);
require IO::Zlib;

=head1 NAME

Chroniton::Restore - implements restoration from backups

=head1 SYNOPSIS

    my $restore = Chroniton::Restore->new($config, $state, $log);
    my @versions = $restore->restorable("/foo/bar");
    $restore->restore($versions[0]);

=head1 METHODS

=head2 new(config, state, log)

Standard config, state, and log objects.  Unless you're
C<Chroniton.pm> you shouldn't be calling this.

=cut

sub new {
    my ($class, $config, $state, $log) = @_;
    die unless $config && $state && $log;
    
    my $self = {config   => $config,
		state    => $state,
		log      => $log, 
	        remove   => [],       
		contents => {},     };

    bless $self, $class;
    
    $log->message("", "loading information about backups");
    foreach my $backup ($state->backups, $state->archives){
	next if !$backup;
	my $contents = $backup->{contents};
	next if !$contents;
	
	my $location   = $backup->{location};
	$log->debug($location, "adding $location to list of known backups");
	
	$self->{contents}->{$location} ||= $self->_load_contents($contents);
    }
    
    return $self; 
}

=head2 restore(file, [force])

Restores the C<Chroniton::File> object represented by C<file>.  If
C<force> is specified, the file will be overwritten if it exists.
(Otherwise, the existence will throw a fatal error.)

Returns the number of files that were successfully restored.

=cut

sub restore {
    my ($self, $file, $force) = @_;
    my $log = $self->{log};
    my $filename = $file->{name};
    my $from     = $file->{location};
    
    $log->fatal("no file specified") if !$filename;
    $log->fatal("don't know where to restore from") if !$from;
    $log->fatal("$filename already exists.  Move it out of the way or ".
		"specify 'force' (DANGEROUS)", undef, 1)
      if -e $filename && !$force;

    my $tmp;

    # deal with compression
    if($file->{archive}){ #&& $file->{type} eq "directory"){
	$tmp = tempdir(CLEANUP => 1);
	$log->fatal($filename, "can't create a temporary directory")
	  if !$tmp;
	
	# archived.  decompress and pretend this never happened
	$log->debug($filename, "$filename is archived, ".
		               "decompressing everything to $tmp!");

	my $archive = "$from/data.tar.gz";
	if(! -e $archive){
	    $log->fatal($archive, "archive $archive doesn't exist");
	}
	
	$Archive::Extract::PREFER_BIN = 1;
	my $ae = Archive::Extract->new(archive => $archive);
	my $status = $ae->extract(to => $tmp);
	
	if(!$status){
	    $log->error("$from/data.tar.gz", "couldn't decompress archive ".
			"$from/data.tar.gz: ". $ae->error);
	    return;
	}
	else {
	    $log->debug("$from/data.tar.gz", "everything extracted OK");
	}
    }

    # now figure out where the backup is
    my $source;
    my $archive = $file->{archive};
    if (!$archive) {
	$source = "$from/$filename";
    }
    else {
	$source = "$tmp/$archive/$filename";
    }
    $log->debug($filename, "attempting to restore $source to $filename");

    # deal with error conditions
    $log->fatal("cannot restore from $source from $from: file does not exist")
      if !-e $source;

    # do the restore, since it appears possible
    my $files_restored = 0;

    if(-d $source){
	# get the contents
	my $contents = $self->{contents}->{$from};

	if($archive){
	    my @files = map {@$_} values %{$contents->{files}};
	    @files = grep {$_->{archive} eq $archive} @files;
	    
	    my %files;
	    foreach(@files){
		my $name = $_->{name};
		$files{$name} = [$_];
	    }
	    
	    $contents->{files} = \%files;
	}
	
	# then do the restore
	$files_restored = $self->_restore_directory($source, $filename, $contents);
    }
    else {
	$files_restored = $self->_restore_file($source, $filename, $file);
					       
    }

    return $files_restored;
}

sub _restore_directory {
    my ($self, $from, $to, $contents) = @_;
    my $log = $self->{log};
    
    $log->debug($from, "restoring (d) $from to $to");
    
    my $files_restored = 0;
    
    # make the directory
    if(-d $from){
	my @subdirs = split m{/}, $to;
	my $d;
	my @errors;
	if(!-d $to){
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
    }

    # then restore to it recursively
    opendir my $dh, $from or $log->error($from, "couldn't inspect $from");
    foreach my $entry (readdir $dh){
	next if $entry eq '..' || $entry eq '.';
	my $source = "$from/$entry";
	my $dest   = "$to/$entry";
	
	if(!-d $source){
	    my $filedata = ($contents->get_file($dest))[0];
	    $files_restored += $self->_restore_file($source, $dest, $filedata);
	}
	else {
	    # recurse!
	    $files_restored += $self->_restore_directory($source, $dest,
							 $contents);
	}
    }   

    # and finally set the attributes on it
    eval {
	my $filedata = ($contents->get_file($to))[0];
	$filedata->apply_metadata($to, $log);
    };
    if($@){
	$log->warning($to, "couldn't apply metadata: $@");
    }
    return $files_restored;
}

sub _restore_file {
    my ($self, $from, $to, $filedata) = @_;

    my $log = $self->{log};
    $log->debug($from, "restoring $from to $to");

    if(!-e $from){
	$log->error($to, "original file $from not found");
	return 0;
    }

    my $status = 1;
    $status = unlink $to if -e $to; # TFM said restoring to an existing file
                                    # would kill it -- it wasn't lying.
    $log->warning($to, "existing destination $to could not be unlinked,".
		       " data may not be restored!") 
      if !$status;
    
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
    
    # and finally set the attributes on it
    eval {
	$filedata->apply_metadata($to, $log);
    };
    if($@){
	$log->warning($to, "couldn't apply metadata: $@");
    }
    return 1;
}

=head2 restorable(filename)

Lists all revisions of all files that are versions of
C<filename>. Returns a list of C<Chroniton::File> objects.

=cut

sub restorable {
    my ($self, $filename) = @_;
    my $log = $self->{log};
    my @results;
    my $count;
    foreach my $root (keys %{$self->{contents}}){
	$log->debug($filename, "looking for $filename in '$root'");
	my @files = $self->{contents}->{$root}->get_file($filename);
	
	foreach(@files){
	    push @results, $_ if $_;
	}
    }
    
    $count = scalar @results;
    
    {
	my %seen;
	@results = 
	  grep {
	      $seen{$_->metadata->{md5}}++ == 0
		unless $_->metadata->{permissions} =~ /^d/ 
	    } @results;
    }
    $log->debug($filename, scalar @results. " unique variants of ".
		           "$filename out of $count total found");
    
    return sort {$a->metadata->{mtime} <=> $b->metadata->{mtime}} @results;
}

sub _load_contents {
    my ($self, $from) = @_;
    my $log = $self->{log};
    my $result;
    eval {
	$result = LoadFile("$from")
    };
    if($@ || !$result->isa("Chroniton::BackupContents")){
	$log->warning($from, "$from may be a corrupt contents file! ($@)");
	return;
    }
    return $result;
}

1;
