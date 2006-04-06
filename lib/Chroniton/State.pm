#!/usr/bin/perl
# State.pm
# Copyright (c) 2006 Jonathan T. Rockway

# keeps tabs on backup state
package Chroniton::State;
use strict;
use warnings;
use YAML qw(LoadFile DumpFile);
use File::Copy;

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
	$log->warning("$dir/$STATEFILE", "state file was corrupt") if $@;
	$self = _rebuild_state($dir); # if this dies, propagate error up
    }

    # TODO: check consistency

    $self->{dir}    = $dir;
    $self->{config} = $config;
    $self->{log}    = $log;
    
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
    
    $log->fatal($@) if($@ || !-e "$dir/$STATEFILE");
    $log->debug("$dir/$STATEFILE", "state was written back ok");
}

sub _rebuild_state {
    # TODO: be smarter about this.
    my $state = {};
    return $state;
}


# autosave
sub DESTROY {
    my $self = shift;
    $self->save;
}

=head1 TODO

Instead of modifying the internals, make some methods for manipulating state.

=cut

1; # loaded ok
