#!/usr/bin/perl
# Chroniton.pm
# Copyright (c) 2006 Jonathan T. Rockway

package Chroniton;
use strict;
use warnings;
use Chroniton::Archive;
use Chroniton::Config;
use Chroniton::State;
use Chroniton::Messages;
use Chroniton::Message;
use Chroniton::Event;
use Chroniton::Backup;
use Chroniton::Restore;
use YAML::Syck qw(DumpFile);
use Lingua::EN::Inflect qw(NO);
use Time::HiRes qw(time);
use Time::Duration qw(ago);

our $VERSION = '0.03';
1;

=head1 Chroniton

=head1 NAME

Chroniton.pm - simple backup system with archiving and incremental backups

=head1 ABSTRACT

This module is the interface to the exciting functionality provided by
the other C<Chroniton::> modules.  The interface is action oriented,
suitable for use by backup client software or even other scripts or
modules.  If you're an end user, see L<chroniton.pl>.

=head1 SYNOPSIS

     my $chroniton = Chroniton->new;
     $chroniton->backup;     
     print $chroniton->summary;
     exit 0;

=head1 TODO and NOTES

Note that the test suite plays around with your filesystem a bit.  It
adds a config file (that you'll want later anyway), and touches /tmp.
I'll fix this Real Soon -- some other Test::* modules need to be
written first.

As always, bug reports, feature request, rants about why this package
is unnecessary, etc., are welcomed.  I'd especially like to hear from
Windows users, since I don't have a Windows machine anywhere, nor do I
understand the semantics of the Windows filesystem.

I'd also like to know if the individual component modules would be
useful to anyone if they were available separately.  Logging has been
done to death, but I think there are some useful features in my
L<Chroniton::Messages> module.  Let me know what you think.

=head1 CONSTRUCTOR

=head2 new (\%args)

Creates a new Chroniton, which encapsulates time itself!  All
arguments are optional, and include:

=over

=item log

The C<Chroniton::Messages> object to store log entries to.

=item config

The C<Chroniton::Config> object to glean configuration information from.

=item interactive

Set to true if it's OK to print informative messages to STDOUT and STDERR.

=item print_errors

Set to true if it's OK to print errors to STDERR, even when C<interactive> is false.

=item verbose

Set to true if you'd like those messages to be verbose.

=back

What's a chroniton, anyway?
L<http://www.gotfuturama.com/Information/Capsules/3ACV14.txt>.

=cut

sub new {
    my ($class, $self) = @_;
    
    eval {
	# load config
	if(!$self->{config}){
	    $self->{config} = Chroniton::Config->new;
	}
	
	# create logger
	if(!$self->{log}){
	    if($self->{verbose}){
		$self->{log} = Chroniton::Messages->new(\*STDERR);
	    }
	    elsif($self->{print_errors}){
		$self->{log} = Chroniton::Messages->new(\*STDERR, "errors");
	    }
	    else {
		$self->{log} = Chroniton::Messages->new();
	    }
	}

	# load state
	if(!$self->{state}){
	    $self->{state} = Chroniton::State->new($self->{config},
						   $self->{log});
	}
	
    };
    if($@){
	die "Error creating chroniton: $@";
    }

    return bless $self, $class;
}

sub _get_log {
    return $_[0]->{log};
}

sub _get_config {
    return $_[0]->{config};
}

sub _get_state {
    return $_[0]->{state};
}

sub backup {
    my $self		  = shift;
    my $config		  = $self->_get_config;
    my $archive_after	  = $config->archive_after;
    my $state		  = $self->_get_state;
    my $log               = $self->_get_log;
    my $last_full_backup  = eval {$state->last_full_backup->{date}} || 0;
    my $last_backup	  = eval {$state->last_backup->{location}}  || undef;
    my $last_backup_time  = eval {$state->last_backup->{date}}      || 0;
    my $contents;

    my $f_ago = ago(time() - $last_full_backup);
    $f_ago = "never" if !$last_full_backup;
    
    my $ago = ago(time() - $last_backup_time);
    $ago = "never" if !$last_backup_time;

    $self->_msg("Last backup was $ago.");    
    $self->_msg("Last full backup was $f_ago.");

    my $days_since_last_full_backup = (time() - $last_full_backup)/86_400;

    if(!$last_full_backup || !-e $last_backup){
	$self->_msg("No backup to increment against.  Forcing full backup.");

	##
	$contents = $self->force_backup;
    }
    elsif ($days_since_last_full_backup > $archive_after){
	$self->_msg("Forcing archive and full backup.");
	eval {
	    
	    ##
	    $contents = $self->force_archive;
	};
	if($@){
	    $log->error(undef, "archive failed");
	}
	##
	$config->{time} = time();
	$contents = $self->force_backup;
    }
    else {
	my $against = $last_backup;
	
	##
	$contents = $self->force_incremental($against);
    }
    
    return $contents;
}

sub force_backup {
    my $self = shift;
    my $state  = $self->_get_state;
    my $log    = $self->_get_log;
    my $config = $self->_get_config;
    my @backup_locations = $config->locations;
    my $backup_storage   = $config->destination;
    
    $self->_msg("Starting full backup.");

    my $contents = Chroniton::Backup::backup($config, $log,
					     [@backup_locations], $backup_storage);

    my $where   = $contents->{location};
    $self->_write_contents($contents, $where);
    
    my $then    = $self->_get_config->{time};
    my $logfile = $self->_finish_up;
    $state->add_backup($where, 1, undef, $then, $logfile);
    $state->save;
    return $contents;
}

sub force_incremental {
    my $self		  = shift;
    my $state		  = $self->_get_state;
    my $log		  = $self->_get_log;
    my $config		  = $self->_get_config;
    my @backup_locations  = $config->locations;
    my $backup_storage	  = $config->destination;
    my $against		  = shift || eval{$state->last_backup->{location}};

    if(!$against){
	$self->_msg("No directory found to increment against!");
	$log->error($against, "no directory found to increment against");
	die "no directory to increment against";
    }

    if(!-r $against || !-d $against){
	$log->fatal("cannot increment against $against", $against);
    }

    $self->_msg("Starting incremental backup against $against.");
    my $contents = Chroniton::Backup::backup($config, $log,
					     [@backup_locations],
					     $backup_storage,
					     $against);
    
    my $where = $contents->{location};
    $self->_write_contents($contents, $where);    
    
    my $then  = $self->_get_config->{time};
    my $dest  = $self->_get_config->destination;
    my $logfile = $self->_finish_up;
    $state->add_backup($where, 0, undef, $then, $logfile);
    $state->save;
    return $contents;
}

sub force_archive {
    my $self   = shift;
    my $log    = $self->_get_log;
    my $config = $self->_get_config;
    my $state  = $self->_get_state;
    my $directory = $config->destination;

    $self->_msg("Starting archive of $directory");
    my $where = Chroniton::Archive::archive($config, $log);
    if(defined $where){
	$self->_msg("Archive completed.");
	$state->clear_backups;
    }
    my $then     = $self->_get_config->{time};
    my $dest     = $self->_get_config->destination;
    my $logfile  = $self->_finish_up;
    my $contents = (-e "$where/contents.yml") ? "$where/contents.yml" : "";
    $state->add_archive($where,  $contents, $then, $logfile);

    if(!defined $where){
	$self->_msg("Something bad happened. See the log ".
		    "$logfile for details.");
    }
    $state->save;
    $self->{restore} = undef; # clear the contents cache in the
			      # restore object, if it exists
    return $where;
}

sub restorable {
    my $self	  = shift;
    my $filename  = shift;
    my $config    = $self->_get_config;
    my $log       = $self->_get_log;
    my $state     = $self->_get_state;
    
    $self->{restore} ||= Chroniton::Restore->new($config, $state, $log);

    $self->_msg("Searching backups for $filename.  This may take a while.");
    return $self->{restore}->restorable($filename);
}

sub restore {
    my $self	   = shift;
    my $file       = shift;
    my $force	   = shift;
    my $config     = $self->_get_config;
    my $state	   = $self->_get_state;
    my $log	   = $self->_get_log;
    
    $self->{restore} ||= Chroniton::Restore->new($config, $state, $log);
    
    my $filename = $file->{name};
    my $from;
    if($file->{archive}) {
	$from = $file->{archive} . " (archived in ". $file->{location}. ")";
    }
    else {
	$from = $file->{location};
    }
    $self->_msg("Restoring $filename from $from");
    my $files = $self->{restore}->restore($file, $force);
    $self->_msg( NO("file", $files). " restored");

    my $logfile = $self->_finish_up;
    $state->add_restore($filename, $from, $config->{time}, $logfile);
    $state->save;

    return $files;
}

sub summary {
    return $_[0]->_get_log->summary;
}

sub errors {
    return $_[0]->_get_log->retrieve("error");
}

sub warnings {
    return $_[0]->_get_log->retrieve("warning");
}

sub _finish_up {
    my $self  = shift;
    my $config= $self->_get_config;
    my $log   = $self->_get_log;
    my $state = $self->_get_state;
    my $then  = $self->_get_config->{time};
    my $dest  = $self->_get_config->destination;
    # save state
    $self->_msg("Writing state information back to disk. ",
		"This may take a while.");
    
    my $logfile;
    if($self->errors == 0 && $self->warnings == 0){
	# no need to save the log... nothing bad happened
	$state->set_last_log(undef);
	$self->_msg("Not writing log to disk - no errors or warnings.");
    }
    else {
	# save log
	$logfile = "$dest/log_$then.yml";
	$state->set_last_log($logfile);
	DumpFile($logfile, $log);
    }

    return $logfile;
}

sub all_ok {
    my $self = shift;
    my $log  = $self->_get_log;
    
}

sub _write_contents {
    my $self	   = shift;
    my $contents   = shift;
    my $where	   = shift;
    my $log	   = $self->_get_log;
    
    $log->debug("$where/contents.yml", "Writing file list to disk");
    eval {
	DumpFile("$where/contents.yml", $contents);
    };
    $log->error("$where/contents.yml", "problem saving file list") if $@;
}

sub _msg {
    my $self = shift;
    print {*STDERR} "[MSG] @_\n" if $self->{interactive};
}

=head1 METHODS

=head2 backup

Performs a backup in accordance with the config file -- full if a full
backup is required, incremental otherwise.  If the configuration dictates
that an archive should performed, it will be.

=head2 force_incremental([against])

Forces an incremental backup against C<against>.  If C<against> isn't
specified, the incremental backup will be performed against the last
backup.  If that doesn't exist, the method will C<die>.

=head2 force_backup

Forces a full backup in accordance with the configuration file.

=head2 force_archive

Archives all backup data in the backup storage directory.

=head2 restorable(filename)

Returns a list of all restorable versions of C<filename>.  The list is
a list of array references, which is formatted according to
L<Chroniton::Restore/FUNCTIONS/restorable>.

=head2 restore(file, [force])

Restores C<file> (a C<Chroniton::File> object as returned by
C<restorable>) to its original location, overwriting it if C<force> is
true.

=head2 summary

Returns a summary of the actions performed, suitable for presenting to
the user when a backup or restore is complete.

=head2 errors

Returns a list of errors encountered during the backup.  Elements of
the list are C<Chroniton::Message> objects.

=head2 warnings

Returns a list of warnings encountered durning the backup.  Elements of
the list are C<Chroniton::Message> objects.

=head1 DIAGNOSTICS

=head2 Error creating Chroniton: $@

Something bad happened while initilizing the object.  Possibilities
include problems loading the configuration, problems creating the
logging object (unlikely), problems restoring the state, or a storm of
cosmic rays hiting your non-ECC RAM.  Make sure your config is sane
and try again.  (More information is printed as C<$@>.)

=head2 Not yet implemented

You're using functionality that doesn't exist.  You shouldn't see this
unless the version number contains a _, in which case it's a
developer's release.

=head1 MORE DOCUMENTATION

See L<chroniton.pl> if you're an end user, or L<Chroniton::Backup>,
L<Chroniton::Restore>, or L<Chroniton::Archive> if you're a developer.
L<Chroniton::State>, L<Chroniton::Config>,
L<Chroniton::BackupContents>, L<Chroniton::Messages>,
L<Chroniton::Message>, and L<Chroniton::Event> are also available for
your perusal.

=head1 CONTRIBUTING

Please send me bug reports (via the CPAN RT), test cases, comments on whether
or not you like the software C<:)>, and patches.  

=head1 AUTHOR

Jonathan Rockway C<< <jrockway at cpan.org> >>.

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

=cut

