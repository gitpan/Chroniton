#!/usr/bin/perl
# Event.pm - [description]
# Copyright (c) 2006 Jonathan Rockway

package Chroniton::Event;
use strict;
use warnings;
use base qw(Chroniton::Message);
use constant (_copy    => 10,
	      _link    => 11,
	      _delete  => 12,
	      _mkdir   => 13,
	     );

=head1 NAME

Chroniton::Event - represents an event to be added to the event log
(L<Chroniton::Messages>).

=head1 SYNOPSIS

     my $log = Chroniton::Messages->new;

     $log->add(Chroniton::Event->mkdir("dir"));
     $log->add(Chroniton::Event->copy("foo", "bar/foo"));
     # etc.

=head1 CONSTRUCTORS

All of the below "methods" actually construct a Chroniton::Event (via
C<Chroniton::Message::_new>), suitable for passing to
C<Chroniton::Messages>.

=head2 event

A generic event.  Arguemtns are filename (that the event applies to), message, and "event_id", an integer.  10-13 are reserved for the below events (copy, link, delete, mkdir).

=cut

sub event {
    my ($class, $filename, $message, $event_id) = @_;
    my $self = $class->_new($filename, $message, "event", 0);
    $self->{event_id} = $event_id;

    return $self;
}

=head2 copy

A file copy event.  Arguments are source filename, destination
filename, time elapsed (optional), and bytes copied (optional).

=cut

sub copy {
    my ($class, $src, $dst, $time, $bytes) = @_;
    my $self = $class->_new($src, "copy $src to $dst", "event", 0);

    $self->{source_file}	=   $src;
    $self->{destination_file}	=   $dst;
    $self->{event_id}		=     10;
    $self->{elapsed_time}       =  $time;
    $self->{bytes}		= $bytes;
    return $self;
}

=head2 link

A file symlink event.  Arguments are source filename and destination
filename.

=cut

sub link {
    my ($class, $src, $dst) = @_;
    my $self = $class->_new($src, "link $src to $dst", "event", 0);

    $self->{source_file}       = $src;
    $self->{destination_file}  = $dst;
    $self->{event_id}	       =   11;
    
    return $self;
}

=head2 delete

A file deletion event.  Argument is the filename that was deleted.

=cut

sub delete {
    my ($class, $file) = @_;
    my $self = $class->_new($file, "remove $file", "event", 0);
    $self->{event_id} = 12;
    
    return $self;
}

=head2 mkdir

A directory creation event.  Argument is the name of the directory that was created.

=cut

sub mkdir {
    my ($class, $dir) = @_;
    my $self = $class->_new($dir, "mkdir $dir", "event", 0);
    $self->{event_id} = 13;
    
    return $self;
}


1;
