#!/usr/bin/perl
# State.pm
# Copyright (c) 2006 Jonathan T. Rockway

# keeps tabs on backup state
package Chroniton::State;
use strict;
use warnings;

use File::Copy;
use Time::HiRes qw(time);
use YAML::Syck qw(LoadFile DumpFile);

my $STATEFILE = "state.yml";

=head1 NAME

Chroniton::State - keeps track of backups between Chroniton invocations

=head1 METHODS

=head2 new (config, log)

Creates a new object, using config as the configuration
(L<Chroniton::Config>), and log as the event log
(L<Chroniton::Messages>).

=cut

sub new {
    my $class = shift;
    my $config = shift;
    my $log    = shift;
    my $self = {};

    my $dir = $config->destination;
    if(-e "$dir/$STATEFILE"){
	# thaw self
	eval {
	    $self = LoadFile("$dir/$STATEFILE");
	};
    }
    if($@ || !-e "$dir/$STATEFILE"){
	my $self = shift;
	$log->warning("$dir/$STATEFILE", "state file was corrupt ($@)") if $@;
	$self = _rebuild_state($dir); # if this dies, propagate error up
    }

    # TODO: check consistency

    $self->{dir}    = $dir;
    $self->{config} = $config;
    $self->{log}    = $log;
    if(!$self->{backups}){
	$self->{backups} = [];
    }
    if(!$self->{restores}){
	$self->{restores} = [];
    }
    if(!$self->{archives}){
	$self->{archives} = [];
    }

    $log->debug("$dir/$STATEFILE", "state loaded ok");
    bless $self, $class;
    return $self;
}

=head2 save

Writes the object to disk for use by future invocations of Chroniton.

=cut

sub save {
    my $self = shift;
    my $config = $self->{config};
    my $log    = $self->{log};
    my $dir    = $self->{dir};

    $log->message("$dir/$STATEFILE", "writing state back to disk");

    delete $self->{config}; # don't want these to persist across invocations 
    delete $self->{log};
    delete $self->{dir};
    
    eval {
	DumpFile("$dir/$STATEFILE", $self);
    };

    $self->{dir}    = $dir;   # we want to do this even if DumpFile dies
    $self->{config} = $config; 
    $self->{log}    = $log;
    
    $log->error("$dir/$STATEFILE", "error writing back state: $@") if($@);
    $log->debug("$dir/$STATEFILE", "state was written back ok");
}

sub _rebuild_state {
    # TODO: be smarter about this.
    my $state = {last_log    => "",
		 backups     => [], 
		 archives    => [],
		 restores    => [], };
    return $state;
}

=head2 clear_backups

Forget about all backups.

=cut

sub clear_backups {
    my $self = shift;
    $self->{backups} = [];
}

=head2 add_backup(location, full?, contents, date, log)

Adds a backup to the memorized backup sets.  Location is the location
of the backups, contents is the path of the contents file, date is
the time of the backup, and log is the location of the logfile.

=cut

sub add_backup {
    my $self = shift;
    my $location = shift;
    my $full     = shift || 0;
    my $contents = shift || "$location/contents.yml";
    my $date     = shift || time();
    my $log      = shift;
    
    push @{$self->{backups}}, {location => $location,
			       type     => ($full) ? "full" : "incremental",
			       contents => $contents,
			       date     => $date,     
			       log      => $log };
}

=head2 add_restore(what, from, date, logfile)

=cut

sub add_restore {
    my ($self, $what, $from, $date, $logfile) = @_;

    push @{$self->{restores}}, {what => $what,
				from => $from,
				date => $date,
				type => "restore",
				log  => $logfile };
}

=head2 add_archive(location, contents, date, log)

=cut

sub add_archive {
    my ($self, $location, $contents, $date, $logfile) = @_;
    push @{$self->{archives}}, {location => $location,
				contents => $contents,
				date     => $date,
				type     => "archive",
				log      => $logfile, };
}

=head2 events

Returns the list of all events (backups, restores, archives).

=head2 backups

Returns the list of backups.

=head2 archives

Returns the list of archives.

=head2 last_backup

Returns the time, in seconds past the epoch, of the last backup.

=head2 last_full_backup

Returns the time of the last full backups.

=cut

sub events {
    my $self = shift;
    return sort {$a->{date} <=> $b->{date}}
      (@{$self->{backups}},
       @{$self->{restores}},
       @{$self->{archives}});
}

sub archives {
    my $self = shift;
    return @{$self->{archives}};
}

sub backups {
    my $self = shift;
    return @{$self->{backups}};
}

sub last_backup {
    my $self = shift;
    return (sort {$b->{date} <=> $a->{date}} @{$self->{backups}})[0];
}

sub last_full_backup {
    my $self = shift;
    my @backups = @{$self->{backups}};
    @backups = grep {$_->{type} eq "full"} @backups;
    @backups = sort {$b->{date} <=> $a->{date}} @backups;
    return $backups[0];
}

=head2 last_log

Returns the path of the most recent log.


=head2 set_last_log(path)

Sets the path to the most recent log file.

=cut

sub last_log {
    my $self = shift;
    return $self->{last_log};
}

sub set_last_log {
    my $self = shift;
    $self->{last_log} = shift;
}

1; # loaded ok
