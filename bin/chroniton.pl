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
use Number::Bytes::Human qw(format_bytes);
use Term::ReadLine;
use Time::Duration qw(ago);
use Time::HiRes qw(time);
use YAML::Syck qw(LoadFile Dump);

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

if(exists $ARGV{'--history'}){
    do_history();
}

if(exists $ARGV{'--list'}){
    do_list();
}

my $then = time();
my $chroniton = Chroniton->new({verbose => $ARGV{'-v'},
				interactive => !$ARGV{'-q'}});
die "couldn't initialize chroniton" if !$chroniton;

# do the operation

if($ARGV{'--backup'}){
    # forced full backup
    $chroniton->force_backup;
}

elsif($ARGV{'--incremental'}){
    # forced incremental backup
    $chroniton->force_incremental;
}

elsif($ARGV{'--archive'}){
    # forced archiving
    $chroniton->force_archive;
}

elsif($ARGV{'--restore'}){
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
    my $filename = $ARGV{'--restore'}->{file};
    my $revision = $ARGV{'--restore'}->{revision};
    my $term = Term::ReadLine->new("chroniton.pl");
    my $file;

    $filename = $term->readline("filename> ") unless $filename;
        
    while(!$file){
	exit 1 if $filename =~ /^(?:q|qu|qui|quit|e|ex|exi|exit)$/;
	my @possibilities = $chroniton->restorable($filename);
	my $i = scalar(@possibilities);
	
	$file = $possibilities[0] and last if $i == 1; # ends loop
	
	if($i > 0){
	    print NO("version", $i), " of $filename available. \n";
	    
	    foreach(@possibilities){
		my $archive  = $_->{archive} ? "*" : "";
		my $ago      =  ago(time - $_->metadata->{mtime});
		$i--;
		my $in = $_->{location};
		if($archive){
		    $in .= $_->{archive};
		}
		
		print "$i) $archive $filename from $ago\n   in $in\n";
		
	    }
	    
	    @possibilities = reverse @possibilities;

	    print "\nEnter revision to restore from, or C-c to quit.\n";
	    while(!defined $revision ||
		  $revision !~ /^\d+$/ ||
		  !exists $possibilities[$revision]){

		$revision = $term->readline("revision> ");
		exit 1 if $revision =~ /^(?:q|qu|qui|quit|e|ex|exi|exit)$/;
		
	    }
	    
	    my $mtime = ago(time -$possibilities[$revision]
			    ->metadata->{mtime});
	    print "Revision $revision (from $mtime) selected.\n";
	    $file = $possibilities[$revision]; # ends loop
	}
	else {
	    print "$filename was not found.  Enter a new filename, or C-c to quit.\n";
	    $filename = $term->readline("filename> ", $filename);
	    # loop around to search for revisions
	}
    }
    eval {
	$chroniton->restore($file, $ARGV{'--force'});
    };
    if($@){
	if($@ =~ /Move it out of the way/){
	    print "*** $filename already exists.  Move it out of the way, ".
	      "or specify --force on the command line.\n";
	    exit;
	}
	else {
	    print "*** $filename could not be restored.\n Error: $@\n";
	    exit;
	}
    }
}

sub do_log {
    my $file = shift;
    no warnings;
    
    if(!-e $file){
	# ignore the user, his choice of logfiles is poor
	my $config = Chroniton::Config->new;
	my $log_o  = Chroniton::Messages->new; 
	my $state  = Chroniton::State->new($config, $log_o);
	$file = $state->last_log;
	die "No log file to view. Try specifying one on the command line." 
	  if !-e $file;
    }
    
    my $log = LoadFile($file);
    die "Couldn't load log '$file' ($@)" if !$log;
    
    my @events = $log->retrieve_all;
    foreach my $event (@events){
	print $event->string($ARGV{-v}, 1). "\n";
    }

    exit 0;
}

sub do_history {
    my $config = Chroniton::Config->new;
    my $log    = Chroniton::Messages->new;
    my $state  = Chroniton::State->new($config, $log);

    my @backups  = sort {$a->{date} <=> $b->{date}}
      ($state->backups, $state->archives);
    
    my $i = $#backups;
    my $now = time();
    foreach my $backup (@backups){
	my $location	 = $backup->{location};
	my $contents_f	 = $backup->{contents};
	my $log_f	 = $backup->{log};
	my $contents	 = LoadFile($contents_f) if $location;
	my $ago		 = ago($now - $backup->{date});
	my $type	 = $backup->{type};	

	my @files	 = $contents->ls;
	my @allfiles	 = map {$contents->get_file($_)} @files;

	my $bytes	 = 0;
	my $time	 = 0;
	my $links	 = 0;
	my $files	 = scalar @files;
	my $directories	 = 0;
	
	map {
	    $bytes += $_->metadata->{size} if !defined $_->{target};
	    $links++ if $_->{target};
	    $directories ++ if $_->metadata->{permissions} =~ /^d/;
	} @allfiles;
	
	$files       = NO("object", $files);
	$directories = NO("directory", $directories);
	$links       = NO("link", $links);

	$type .= " backup" if($type ne "archive");

	print "---\n";
	print "$i: $type to $location\n   $ago\n";
	print "   ";
	if($type eq "archive"){
	    my $asize = format_bytes((stat "$location/data.tar.gz")[7]);
	    print "$asize on disk, ";
	}


	print format_bytes($bytes).
	      " in $files ($directories and $links)\n";

	# load the log after something's been printed (to keep the
	# user awake)
	if(defined $log_f && -e $log_f){
	    my $log	   = LoadFile($log_f);
	    my $errors	   = scalar $log->retrieve(  "error"  );
	    my $warnings   = scalar $log->retrieve( "warning" ); 

	    my $errors_m   = NO("error",   $errors);
	    my $warnings_m = NO("warning", $warnings);

	    print " $errors_m and $warnings_m encountered:\n";
	    if($errors){
		my @errors   = $log->retrieve("error");
		my @warnings = $log->retrieve("warning"); 
		foreach my $e (@errors,@warnings){
		    print "  ". $e->{message}. "\n";
		}
	    }
	}
	
	$i--;
    }

    exit 0;
}

sub do_list {
    my $config = Chroniton::Config->new;
    my $log    = Chroniton::Messages->new;
    my $state  = Chroniton::State->new($config, $log);

    my @backups = reverse sort {$a->{date} <=> $b->{date}} $state->backups;
    my $backup = $backups[0];
    if(!$backup){
	print {*STDERR} "*** No backups to examine.  Stop.\n";
	exit 1;
    }
    my $contents_l = $backup->{contents};
    my $contents;
    eval {
	$contents = LoadFile($contents_l);
    };
    if($@){
	die "Error: $@";
    }
    
    my @files = sort $contents->ls;
    print join("\n", @files). "\n";
    exit 0;
}

sub do_config {
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

chroniton.pl - interface to the chroniton backup system

=head1 VERSION

This document refers to chroniton.pl version 0.02, C<$Revision: $>.

=head1 SYNOPSIS

=head2 Setting up Chroniton

Before you do anything else, run C<chroniton.pl --configure>.  This
will create a sample configuration file and open it in your C<$EDITOR>
of choice.  After you modify this file, you can edit it again with the
C<--configure> option; it won't erase your changes.

For the format of the configuration file, see L</CONFIGURATION>.  An
example of a configuration file:

     ---
     archive_after: 7
     backup_locations:
      - /Users/Shared
      - /Users/jon
     storage_directory: "/mnt/backups"
     exclude:
      - /Library/Caches
      - /tmp
      - /.cpan

This will cause chroniton to backup everything in /Users/Shared and
/Users/jon, except for filenames that match any of the excludes.  It
will automatically archive your backups every 7 days (and then
immediately do a fresh full backup).

Keep in mind that the file format is fairly strict.  Spaces, in
particular, have meaning, and you'll get errors if the file isn't
valid YAML.  See L<YAML> for more details about YAML.  C<ysh> is a
small program included with YAML that lets you interactively play with
YAML -- give it a try if you've never used YAML before.

Also remember that the excludes are regular expressions, so C</.cpan>
matches /foo/bar/.cpan/5.8.6 and /home/jon/.cpanplus/BUILD (and many
other things).  Please see L<perlre> for more information on regular
expressions.

=head2 Backing up your data

After you've configured chroniton to your satisfaction, run

     chroniton.pl

to do an initial full backup.  If you're interested in exactly what it's doing, try 

     chroniton.pl --verbose

to have chroniton print more information to your terminal.

If there are any errors (or warnings), they'll be printed to your
terminal, as well as to a log file.  You can review the most recent
logfile by typing

     chroniton.pl --log

Sometimes something Really Bad happens and chroniton has to exit
immediately -- in this case it saves the logfile to
~/Library/Logs/chroniton (if ~/Library/Logs exists, otherwise it just
dumps the log in your home directory).  You can review an arbitrary logfile by running:

     chroniton.pl --log /path/to/the/log

The logs are YAML dumps, so they should be understandable if you
C<cat> them.  In fact, there's often more information in the raw dump
than what C<chroniton.pl --log> prints, so if you're not sure exactly
what's going wrong, take a look at the raw file.

Once you have an inital backup, subsequent invocations of
C<chroniton.pl> will only save the changes between your filesystem and
the last backup.  To force C<chroniton.pl> to do a full backup, simply run:

     chroniton.pl --backup

On the rare occasion that you'd like to perform an incremental backup
against chroniton's wishes, you can run

     chroniton.pl --incremental

If you don't have any other backup to increment against, though, that
command will exit with an error.

=head2 Seeing what backups you have

After you've been using chroniton for a while, you'll probably want to
check on what backups you have.  To do that, just run:

     chroniton.pl --history

That will print something that looks like:

     ---
     3: archive to /tmp/backup/archive_2006-04-20T08:24:33
        20 hours and 14 minutes ago
        6.1K on disk, 15K in 11 objects (6 directories and no links)
     ---
     2: full backup to /tmp/backup/backup_2006-04-21T04:36:37
        2 minutes and 21 seconds ago
        6.9K in 5 objects (2 directories and no links)
     ---
     1: full backup to /tmp/backup/backup_2006-04-21T04:37:44
        1 minute and 14 seconds ago
        170 bytes in 1 object (1 directory and no links)
      3 errors and no warnings encountered:
     couldn't copy /Users/Shared/.DS_Store to /tmp/backup/backup_2006-04-21T04:37:44//Users/Shared/.DS_Store: No such file or directory
     couldn't copy /Users/Shared/.localized to /tmp/backup/backup_2006-04-21T04:37:44//Users/Shared/.localized: No such file or directory
     couldn't copy /Users/Shared/SC Info to /tmp/backup/backup_2006-04-21T04:37:44//Users/Shared/SC Info: No such file or directory
     ---
     0: incremental backup to /tmp/backup/backup_2006-04-21T04:38:53
        5 seconds ago
        6.9K in 5 objects (2 directories and no links)

The most recent backup is on the bottom (0), the oldest is at the top
(3).  Note that this command may take some time to run, since it's
loading the backup summaries into memory in order to compute the nice
statistics.  If you have hundereds of backups, you might want to use
this opportunity to obtain a caffeniated beverage.

To get a list of the files in the most recent backup, run:

     chroniton.pl --list

This is much faster than running C<find> in the backup directory (and
equally effective).

=head2 Scheduling automatic backups

After you've created a config file (and tested it by doing a
non-automatic backup), just add a line that looks like:

    0 3 * * * chroniton.pl --quiet

to your C<crontab>. (See C<crontab(5)> in you system's manual if don't
understand the above syntax.)

The C<--quiet> option tells
chroniton to not print any (non-error) messages.  This will save you
the trouble of receiving an e-mail every day informing you that
chroniton ran last night.  If you I<do> get a message, you'll know
something bad happened -- check the log with C<chroniton.pl --log>.

=head2 Archiving data

After a while, it becomes almost useless to have dumps of your
filesystem laying around.  Archiving consolidates several backups into
one compressed file, dramatically saving disk space.

You can configure chroniton to archive your backups every C<n> days by
setting the C<archive_after> configuration directive (see
L</CONFIGURATION> or L</SYNOPSIS/Settng up Chroniton>).  If you'd like
to archive things manually, run

     chroniton.pl --archive

Note that the restore command automatically searches archives, so you don't have
to worry about losing track of old files.

=head2 Restoring data

Restoring from a backup is just as easy as creating the backup.  To
restore a single file, run

     chroniton.pl --restore /the/filename

(C</the/filename> is the full path of the file that you want to
restore).  If there's only one version of C</the/filename> in your
backups, it will automatically be restored its original location.
If there are multiple versions, you'll be asked to select the version
you want:

     2 versions of /Users/Shared/.DS_Store available. 
     1) * /Users/Shared/.DS_Store from 21 hours ago
        in /tmp/backup/archive_2006-04-20T08:24:33/backup_2006-04-20T08:24:29
     0)  /Users/Shared/.DS_Store from 1 minute and 36 seconds ago
        in /tmp/backup/backup_2006-04-21T05:00:49

     Enter revision to restore from, or C-c to quit.
     revision> _

Just type the number that corresponds to the revision you want, or
Control-c to quit.

To save yourself this step and automatically restore the latest version, run

     chroniton.pl --restore /the/filename 0

The 0 in the command corresponds to the 0 in the listing above.

Note that chroniton will never overwrite an existing file.  If you
want it to, specify C<--force> on the commandline.

Restoring directories is the same as restoring files, but versions
aren't as meaningful in this case.  Each backup is a considered a
"version" regardless of whether or not the directory or its contents
changed.  Like files, they won't be restored over an exisiting
directory unless you C<force> them to be.

Note that directories won't be recognized if you attach a
trailing slash (as in, C</directory/>), so don't do that.

=head1 CONFIGURATION

Chroniton is configured via a config file (config.yml) stored in a
"Chroniton" directory in your "application data directory", as
determined by C<File::HomeDir>.  In UNIX, this is C<~/chroniton>, on
Mac OS X, this is C<~/Library/Application Support/Chroniton>.

Options are (as of version 0.02):

=over

=item backup_locations

A list of directories to backup.

=item storage_directory

Where your backups (and chroniton state information) should be stored.
It must be a real directory, not a link to one.  It will be created if
it doesn't exist.

=item exclude

A list of regular expressions.  If a path is matched by one of these
regular expressions, it is not backed up.  If you're not familiar with
Perl's regular expression syntax, please read L<perlre>.  If you'd
like to see what matches and what doesn't, run chroniton in verbose
mode -- a message is printed for every file that is skipped due to
your exclude rules.

=back

For more information about configuring chroniton, see L<Chroniton::Config>.

=head1 SECURITY CONSIDERATIONS

Many people seem to insist on running software like chroniton as
root without having any good reason to.  Chroniton is designed to back
up a user's home directory on a regular basis.  If there are files in
a user's home directory that he can't read, he probably won't miss them
if they disappear.

If you're going to run as root, though, please keep the following
points in mind:

=over

=item Writable C<storage_directory>

If other users can write to C<storage_directory>, they could carefully
replace directories that chroniton creates with symlinks.  This
would result in chroniton writing to whatever directory the link
targets.  If you're running as root, any user with write permission to
the backup target could cause Chroniton to overwrite the password file
(or any other file on the filesystem).

I mention this because it's difficult to create unwritable external
volumes in Mac OS X.

Example exploit: User M's home directory is backed up every night at
1:00AM by root.  User M creates a directory inside his home directory
(we'll call it C</home/haxor/etc>, and adds a file called "passwd".
At 1:00, M checks ps and notes that chroniton has started.  He quickly
replaces C</storage_directory/backup_timestamp/home/haxor/etc> with a
symlink to the real C</etc>.  When chroniton copies
C</home/haxor/etc/passwd> to the storage directory, it will instead
copy the file over the existing C</etc/passwd>, rendering the system
unusable, or worse, 0wned by User M.

All of this should be obvious to anyone with any UNIX administration
experience.  If you're on a multi-user system, give everyone his own
storage directory, that only he can read, and have him run his own
chroniton process.  Better yet, use a backup solution that's
designed for multi-user systems, like TSM (*shudder*).

=back

=head1 OPTIONS

Please do not specify more than one operation.  If you do, the results
are undefined, and you may lose data!

=over

=item --backup

Performs a full backup, ignoring any option in the configuration file
that would cause Chroniton to perform an incremental backup or archive.

=item --incremental

If a full backup exists, creates an incremental backup against the
latest full backup.  Exits with an error if there is no full backup to
increment against.

=item --archive

Archives all full and incrmental backups in the backup storage
directory.  Exits with an error if there are no backups to archive.

=item --restore [<file>] [<revision>]

=for Euclid
     revision.type: int

Restores the file named by C<file>.  If there are multiple revisions
of C<file> available, the user is prompted to select one (unless
C<revision> is specified, in which case the revision sepcified by the
value of C<revision> is restored).  Revisions are numbered such that 0
is the most recent and -1 is the oldest.

=item --config[ure]

Opens the configuration file in C<$EDITOR> for editing.  Other options are ignored.

=item --log [<file>]

Prints out the most recent log, or the file specified by C<file>.

=item --history

Prints out a summary of recent backups.

=item --list

Print out the name of every file in the most recent backup.

=item --force

Force chroniton to do something that it shouldn't.  DANGEROUS.

=item -[-]q[uiet]

quiet, suppress all messages

=item -[-]v[erbose]

verbose, print all messages

=item --version

Prints the version number.

=item --usage

Prints a usage summary.

=item --help

Prints this message.

=item --man

Displays the manual page.

=back

=head1 AUTHOR

Jonathan Rockway C<< <jrockway AT cpan.org> >>

=head1 BUGS

Report to RT, L<http://rt.cpan.org/Public/Bug/Report.html?Queue=Chroniton>.

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




