#!/usr/bin/perl
# Chroniton.pm
# Copyright (c) 2006 Jonathan T. Rockway

package Chroniton;
use strict;
use warnings;
use Chroniton::Config;
use Chroniton::State;
use Chroniton::Messages;
use Chroniton::Message;
use Chroniton::Event;
use Chroniton::Backup;
use YAML qw(DumpFile);

our $VERSION = '0.01_1';
1;

=head1 Chroniton

=head1 NAME

Chroniton.pm - main interface to the Chroniton backup system.

This module is the interface to the exciting functionality provided by
the other C<Chroniton::> modules.  The interface is action oriented,
suitable for use by backup client software or even other scripts or modules.

=head1 SYNOPSIS

     my $chroniton = Chroniton->new;
     $chroniton->backup;     
     print $chroniton->summary;
     exit 0;

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
	    $self->{log} = Chroniton::Messages->new(\*STDERR) if $self->{verbose};
	    $self->{log} = Chroniton::Messages->new           if !$self->{verbose};
	    
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
    my $last_full_backup  = $state->{last_full_backup} || 0;
    my $last_backup	  = $state->{last_backup} || 0;
    my $where;
    
    if(!$last_full_backup || !$last_backup){
	$self->_msg("No backup to increment against.  Forcing full backup.");

	##
	$where = $self->force_backup;
    }
    else {
	my $days_since_last_full_backup = (time() - $last_full_backup)/86_400;
	
	if($days_since_last_full_backup > $archive_after){
	    $self->_msg("Last full backup was at $last_full_backup.  ".
			"Forcing archive and full backup.");
	    eval {

		##
		$where = $self->force_archive;
	    };
	    if($@){
		$log->error(undef, "archive failed");
	    }
	    
	    ##
	    $where = $self->force_backup;
	}
	else {
	    my $against = $state->{last_backup_directory};
	    $self->_msg("Last full backup was at $last_full_backup. Starting incremental ".
			"against $against.");

	    ##
	    $where = $self->force_incremental($against);
	}
    }
    
    return $where;
}

sub force_backup {
    my $self = shift;
    my $state  = $self->_get_state;
    my $log    = $self->_get_log;
    my $config = $self->_get_config;
    my @backup_locations = $config->locations;
    my $backup_storage   = $config->destination;

    $self->_msg("Starting full backup.");

    my $where = Chroniton::Backup::backup($config, $log,
					  [@backup_locations], $backup_storage);
    
    $state->{last_type}			  = "full";
    $state->{last_backup}		  = $config->{time};
    $state->{last_backup_directory}	  = $where;
    $state->{last_full_backup}		  = $config->{time};
    $state->{last_full_backup_directory}  = $where;
    
    $self->_write_contents($where);    
    $self->_finish_up;
    return $where;
}

sub force_incremental {
    my $self		  = shift;
    my $state		  = $self->_get_state;
    my $log		  = $self->_get_log;
    my $config		  = $self->_get_config;
    my @backup_locations  = $config->locations;
    my $backup_storage	  = $config->destination;
    my $against		  = shift || $state->{last_backup_directory};

    if(!$against){
	$self->_msg("No directory found to increment against!");
	$log->error($against, "no directory found to increment against");
	die "no directory to increment against";
    }

    if(!-r $against || !-d $against){
	$log->fatal("cannot increment against $against", $against);
    }

    $self->_msg("Starting incremental backup against $against.");
    my $where = Chroniton::Backup::backup($config, $log,
					  [@backup_locations], $backup_storage, $against);
    
    $state->{last_type}			  = "incremental";
    $state->{last_backup}		  = $config->{time};
    $state->{last_backup_directory}	  = $where;
    
    $self->_write_contents($where);    
    $self->_finish_up;
    return $where;
}

sub force_archive {
    die "Not yet implemented.";
}

sub restorable {
    die "Not yet implemented.";
}

sub restore {
    die "Not yet implemented.";
}

sub summary {
    return ($_[0])->_get_log->summary;
}

sub _finish_up {
    my $self  = shift;
    my $log   = $self->_get_log;
    my $state = $self->_get_state;
    my $then  = $self->_get_config->{time};
    my $dest  = $self->_get_config->destination;
    # save state
    $self->_msg("Writing state information back to disk.  This may take a while.");
    
    if($log->retrieve("error") == 0 && $log->retrieve("warning") == 0){
	$state->{last_log} = "";
	$self->_msg("Not writing log to disk - no errors or warnings.");
    }
    else {
	$state->{last_log} = "$dest/log_$then.yml";
	DumpFile("$dest/log_$then.yml", $log);
    }

    $state->save;
}

sub _write_contents {
    my $self  = shift;
    my $where = shift;
    my $log   = $self->_get_log;

    my @files = $log->retrieve("event");
    @files = grep {$_->{event_id} == 10 || $_->{event_id} == 11; } @files;

    $log->debug("$where/contents.yml", "Writing file list to disk");
    eval {
	DumpFile("$where/contents.yml", \@files);
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
backup is required, incremental otherwise.  If the config dictates
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
a list of array references, which are in the following_format:

     [filename, location_of_backup, modification_date]

C<filename> is the original filename, C<location_of_backup> is where
the backup is located, and C<modification_date> is the date when the
file was last modified.

=head2 restore(path, [from])

Restores C<path> to its original location on the filesystem.  If the
file already exisits, this method will C<die>.  If you want to restore
a file that exists, do it with L<cp|cp(1)>.

=head2 summary

Returns a summary of the actions performed, suitable for presenting to
the user when a backup or restore is complete.

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
L<Chroniton::Restore>, or L<Chroniton::Archive> if you're a
developer.

If you're still confused, mail the author (but don't expect a reply if
the question is answered in This Fine Manual.)

=head1 CONTRIBUTING

Please send me bug reports (via RT), test cases, comments on whether
or not you like the software, and patches!  I always have time to
reply to intelligent commentary.

=head1 AUTHOR

Jonathan Rockway C<jrockway at cpan.org>.

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

