#!/usr/bin/perl
# chroniton.pl - backup/archiving solution for individual workstations
# Copyright (c) 2006 Jonathan T. Rockway

use strict;
use warnings;

use Chroniton::Config;
use Chroniton::Messages;
use Chroniton::State;
use Chroniton;

use Getopt::Euclid;
use Lingua::EN::Inflect qw(NO);
use Term::ReadLine;
use Time::Duration qw(ago);
use Time::HiRes qw(time);
use YAML qw(LoadFile);

my $VERSION = $Chroniton::VERSION;

die "Can't be verbose and quiet simultaneously!" 
  if $ARGV{'-q'} && $ARGV{'-v'};

if(exists $ARGV{'--config'}){
    # try to make a config file or edit one
    do_config();
}

if(exists $ARGV{'--log'}){
    # show the log    
    do_log($ARGV{'--log'});
}

my $then = time();
my $chroniton = Chroniton->new({verbose => $ARGV{'-v'},
				interactive => !$ARGV{'-q'}});
die "couldn't initialize chroniton" if !$chroniton;

# do the operation

if($ARGV{'--mode'} eq "full"){
    # forced full backup
    $chroniton->force_backup;
}

elsif($ARGV{'--mode'} eq "incremental"){
    # forced incremental backup
    $chroniton->force_incremental;
}

elsif($ARGV{'--mode'} eq "archive"){
    # forced archiving
    $chroniton->force_archive;
}

elsif($ARGV{'--mode'} eq "restore"){
    do_restore();
}

else {
    # normal backup
    $chroniton->backup;
}

# print summary
if(!$ARGV{'-q'}){
    print {*STDERR} $chroniton->summary;
    
    my $now  = time;
    my $dur  = $now - $then;
    
    print {*STDERR} "Duration: $dur seconds\n";
}

exit 0;

# __ end of main __

sub do_restore {
    # restore
    my $filename = $ARGV{"--file"};
    my $revision = $ARGV{"--revision"};
    my $term = Term::ReadLine->new("chroniton.pl");
    my $version;

    $filename = $term->readline("filename> ") unless $filename;
    
    while(!$version){
	my @possibilities = $chroniton->restorable($filename);
	{ 
	    my %seen;
	    @possibilities = grep {$seen{$_->[1]}++ == 0} @possibilities;
	}
	
	my $i = scalar(@possibilities);
	$version = $possibilities[0]->[0] and last if $i == 1; # ends loop
	
	if($i > 0){
	    print NO("version", $i). " of $filename available. \n";
	    
	    foreach(@possibilities){
		my $permissions = $_->[2];
		my $owners = join(' ', ($_->[4], $_->[5]));
		
		print " ".--$i.") $filename from ".
		  ago(time - $_->[1]);
	    }

	    print "\nEnter revision to restore from, or C-c to quit.\n";
	    $revision = "not a number";
	    while($revision !~ /^\d+$/ || !exists $possibilities[$revision]){
		$revision = $term->readline("revision> ");
		exit 1 if $revision =~ /^(?:q|qu|qui|quit)$/;
	    }
	    
	    my $mtime = ago(time - $possibilities[$revision]->[1]);
	    print "Revision $revision (from $mtime) selected.\n";
	    $version = $possibilities[$revision]->[0]; # ends loop
	}
	else {
	    print "$filename was not found.  Enter a new filename, or C-c to quit.\n";
	    $filename = $term->readline("filename> ", $filename);
	    exit 1 if $filename =~ /^(?:q|qu|qui|quit)$/;
	    # loop around to search for revisions
	}
    }
    
    $chroniton->restore($filename, $version, $ARGV{'--force'});
}

sub do_log {
    my $file = shift;
    no warnings;
    
    if(!-e $file){
	# ignore the user, his choice of logfiles is poor
	my $config = Chroniton::Config->new;
	my $log_o  = Chroniton::Messages->new; 
	my $state  = Chroniton::State->new($config, $log_o);
	$file = $state->{last_log};
	die "No log file to view. Try specifying one on the command line." 
	  if !-e $file;
    }
    
    my $log = LoadFile($file);
    die "Couldn't load log '$file'" if !$log;
    
    my @events = $log->retrieve_all;
    foreach my $event (@events){
	print $event->string($ARGV{-v}, 1). "\n";
    }

    exit 0;
}

sub do_config {
    require Chroniton::Config;
    my $config_file = Chroniton::Config->config_file;
    
    # create a blank one if needed
    Chroniton::Config->_create($config_file); 
    
    # then exec the editor on it
    my $editor = $ENV{EDITOR};
    $editor = "emacs" if !$editor;
    exec($editor, $config_file);
}

__END__

=head1 NAME

chroniton.pl - Interface to the Chroniton backup system

=head1 VERSION

This document refers to chroniton.pl version 0.01_2.

=head1 CONFIGURATION

Chroniton is configured via a config file (config.yml) stored in a
"Chroniton" directory (in your application data directory, as
determined by C<File::HomeDir>.

Options are (as of version 0.01_2):

=over

=item backup_locations

A list of directories to backup.

=item storage_directory

Where your backups (and Chroniton state information) is stored.  Must
be a directory, not a link to one.

=back

=head1 OPTIONS

=over

=item -q

quiet, suppress all messages

=item -v

verbose, print all messages

=item --mode <mode>

=for Euclid:
     mode.default: "auto"

Specify mode of operation: (full | incremental | archive | auto | config)

=over 

=item full

Performs a full backup, ignoring any option in the configuration file
that would cause Chroniton to perform an incremental backup or archive.

=item incremental

If a full backup exists, creates an incremental backup against the
latest full backup.  Exits with an error if there is no full backup to
increment against.

=item archive

Archives all full and incrmental backups in the backup storage
directory.  Exits with an error if there are no backups to archive.

=item auto

The default action.  Reads the configuration file, determines a
sequence of full, incremental, or archive operations to execute, and
performs these operations.

=item restore

Restores the file (or directory) specified by the C<--file> option.
If the file already exists, exits with an error.  If C<--force> is
specified, restore will replace pre-existing file.  (force is
DANGEROUS: entire directory trees may be irrevocably wiped out,
RECURSIVELY!  Please refer to L</COPYRIGHT> before C<--force>-ing a
restore.)

=back

=item --file <file>

Specifies the file to act upon.  (i.e. for restore).

=item --config

Opens the configuration file in $EDITOR for editing.  Other options are ignored.

=item --log [<file>]

Prints out the most recent log, or the file specified by <file>.

=item --force

Force chroniton to do something that it shouldn't.  DANGEROUS.

=item --version

=item --usage

=item --help

=item --man

=back

=head1 AUTHOR

Jonathan Rockway C<jrockway AT cpan.org>

=head1 BUGS

Report to RT.

=head1 COPYRIGHT

Chroniton is Copyright (c) 2006 Jonathan Rockway.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307,
USA.




