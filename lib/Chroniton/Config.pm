#!/usr/bin/perl
# Config.pm
# Copyright (c) 2006 Jonathan Rockway

package Chroniton::Config;
use strict;
use warnings;
use File::HomeDir;
use YAML qw(LoadFile DumpFile);
use Time::HiRes qw(time);
use Carp;

sub new {
    my $class = shift;
    my $config = {};
    my $config_file = $class->config_file();
    
    eval {
	$config = LoadFile($config_file);
    };
    
    if($@ || !defined $config->{backup_locations}){
	$class->_create($config_file);
    }
    
    my $self = $config;
    
    ## validate
    # die "No valid backup locations found"
    #   if !$self->{backup_locations} || 
    #	$self->{backup_locations}->[0] eq "delete_this_entry";
    # XXX: this foobars my unit tests...

    my $dest = $self->{storage_directory};
    die "configuration does not specify a backup destination" unless defined $dest;

    mkdir $dest;
    die "Backup destination $dest does not exist"     if !-e $dest;
    die "Backup destination $dest is not a directory" if !-d $dest;
    die "Backup destination $dest is not writable"    if !-w $dest;

    warn "nowhere to backup!" if !$self->{backup_locations};
    if($self->{backup_locations}->[0] eq "delete_this_entry"){
	warn "warning: Using unedited config file.";
	shift @{$self->{backup_locations}};
    }
    
    foreach my $location (@{$self->{backup_locations}}){
	die "Cannot backup location $location: not a directory" 
	  if !-d $location;
	die "Cannot backup location $location: not readable" 
	  if !-r $location;
	
    }
    
    $self->{time} = time;
    bless $self, $class;
}

sub destination {
    return $_[0]->{storage_directory};
}

sub locations {
    return @{$_[0]->{backup_locations}};
}

sub config_file {
    return  File::HomeDir->my_data. "/chroniton/config.yml";
}

sub archive_after {
    return $_[0]->{archive_after};
}

sub _blank_config {
    return {
	    storage_directory => "/tmp",
	    backup_locations  => [("delete_this_entry", File::HomeDir->my_home,
				   "/etc")],
	    archive_after => "7",
	   };
}

sub _create {
    my $class = shift;
    my $config_file = shift;
    return if -e $config_file;
    
    $config_file =~ m{^(.+)/[^/]+$};
    my $dir = $1;
    mkdir $dir;

    my $config = $class->_blank_config();
    DumpFile("$config_file", $config);
}

1;

__END__

=head1 NAME

Chroniton::Config - manages config file for Chroniton

=head1 SYNOPSIS

     my $config = Chroniton::Config->new;

=head1 METHODS

=head2 new

Creates an instance.  Takes no arguments.

=head2 destination

Returns the directory where the backup should be placed.

=head2 locations

Returns a list of directories to be backed up. 

=head2 config_file

Returns the path to the config file.

=head2 archive_after

Returns the number of days between archiving operations.

=head2 Chroniton::Config->_create

Creates an empty config file.
