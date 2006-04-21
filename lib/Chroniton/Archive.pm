#!/usr/bin/perl
# Archive.pm
# Copyright (c) 2006 Jonathan T. Rockway
package Chroniton::Archive;

use strict;
use warnings;

use Archive::Tar;
use Chroniton::Event;
use Chroniton::Messages;
use DateTime;
use YAML::Syck qw(LoadFile DumpFile);
require IO::Zlib; # to make sure we can gzip this

=head1 NAME

Chroniton::Archive - compresses old backups, but keeps metadata easily
                     accessible

=head1 SYNOPSIS

=head1 METHODS

=head2 archive($config, $log)

Archive all backups in the backup storage directory.  Creates a folder
called archive_<date> containing three files, C<data.tar.gz>, the
compessed tape archive of all data in the backups, C<logs.tar.gz>, all
log files found in the backup storage directory, and C<contents.yml>,
the (usual) serialized file list.

=cut

sub archive {
    my ($config, $log) = @_;
    my $directory = $config->destination;
    $log->debug($directory, "starting archive of $directory");
    
    my @backups;
    my @logs;
    
    my $status = opendir(my $DH, $directory);
    if(!$status){
	$log->error($directory, "can't open $directory for inspection: $!");
	return;
    }
    
    my @files = readdir $DH;
    closedir $DH;

    chdir $directory;

    foreach my $file (@files){
	next if $file eq ".." || $file eq ".";
	if ($file =~ /^log_.+.yml/){
	    push @logs, $file;
	}
	elsif ($file !~ /^archive/ && -e "$file/contents.yml"){
	    push @backups, $file;
	}
	else {
	    if($file ne "state.yml" && $file !~ /^archive_/){
		$log->warning("$directory/$file",
			      "$file shouldn't be in the backup directory");
	    }
	}
    }

    my $date = DateTime->now();
    
    if(!@logs && !@backups){
	$log->message($directory, "no logs or backups to archive!");
	return 0;
    }
    
    # make the archive directory
    my $archive_dir = "$directory/archive_$date";
    mkdir $archive_dir;    
    if(!-d $archive_dir){
	$log->error($directory, "can't create $archive_dir");
	return;
    }
    $log->add(Chroniton::Event->mkdir($archive_dir));

    if(@logs){
	# archive the logs and clean them up
	$log->debug("", "compressing old logfiles");
	my $logs = Archive::Tar->new();
	$logs->add_files(@logs);
	$status = $logs->write("$archive_dir/logs.tar.gz", 1, "logs");
	if(!$status){
	    my $error = $logs->error;
	    $log->error("$archive_dir/logs.tar.gz",
			"couldn't write out logs: $error");
	    return;
	}
	
	# cleanup logfiles
	$log->debug("", "cleaning logs (@logs)");
	foreach my $logfile (@logs){
	    $status = unlink $logfile;
	    if(!$status){
		$log->warning($logfile,
			      "couldn't unlink old logfile $logfile: $!");
	    }
	}
    }
    else {
	$log->debug("", "no logs to archive");
    }

    if(!@backups){
	$log->debug("", "no backups, therefore ending early");
	# no need to do any of this stuff
	return $archive_dir; # no errors, just nothing to do.
    }

    # make a master contents file
    $log->debug("", "creating master ToC from @backups");
    my $contents = Chroniton::BackupContents->new("archive:$archive_dir");
    foreach my $backup (@backups){
	my $bcontents;
	my @keys;
	eval {
	    $bcontents = LoadFile("$backup/contents.yml");
	    @keys = $bcontents->ls;
	};
	if($@){
	    $log->warning("$backup/contents.yml",
			  "couldn't load contents.yml from $backup: $@");
	      next;
	}

	# coalesce the files into the master set
	foreach my $name (@keys){
	    my @files = $bcontents->get_file($name);
	    foreach my $file (@files){
		$file->{archive} = $file->{location};
		$file->{archive} =~ s/^$directory//;
		$file->{location} = $archive_dir;	
		$contents->add_object($file);
	    }
	}
    }

    # write it out
    eval {
	DumpFile("$archive_dir/contents.yml", $contents);
    };
    if($@){
	$log->warning("$archive_dir/contents.yml",
		      "couldn't write backup description to ".
		      "$archive_dir/contents.yml: $@");
    }
    
    # archive the backup data
    # we need a real tar here.
    $log->debug("", "creating tape archive of @backups");
    my @tar_command = ("tar", "czf", "$archive_dir/data.tar.gz", @backups);
    $status = system(@tar_command);
    if($status != 0){
	$log->error("$archive_dir/data.tar.gz",
		    "problem creating tarfile of [@backups]: error $?");
	return; # clean up other stuff?
    }
    
    # wipe out the old backups
    $log->debug("", "removing @backups");
    foreach my $backup (@backups) {
	$status = system("rm", "-rf", "$backup");
	if($status != 0){
	    $log->warning($backup, "couldn't rm -rf $backup: error $?");
	}
	else {
	    $log->add(Chroniton::Event->delete($backup));
	}
    }
    
    return $archive_dir;
}

1; # ok
