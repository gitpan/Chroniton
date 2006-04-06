#!/usr/bin/perl
# Error.pm 
# Copyright (c) 2006 Jonathan T. Rockway

package Chroniton::Message;
use strict;
use warnings;
use Time::HiRes qw(time);
use Carp qw(longmess);

=head1 NAME

Chroniton::Message - a message to be added to a C<Chroniton::Messages> queue.

=head1 SYNOPSIS

See L<Chroniton::Messages>.

=head1 CONSTRUCTORS

=head2 _new (file, message, type, level)

Creates a new instance.  File is the filename that message applies to.
Type is "error", "warning", "message", or "debug".  Level is the
numeric severity level (0 being a debugging message, 100 meaning that an
explosion is imminent).

Really for Internal Use Only, hence the _ prefix.

=cut

sub _new {
    my $class = shift;
    my ($file, $message, $type, $level) = @_;
    my $self = {file	 => $file,
		message	 => $message,
		type	 => $type,
		level	 => $level,
		time	 => time,
		id       => -1};

    if(defined $type && $type eq "error"){
	# probably only need the first two, but use them all for completeness
	$self->{'!'}  = $!;
	$self->{'@'}  = $@;
	$self->{'?'}  = $?;
	$self->{'^E'} = $^E;
	$self->{backtrace} = longmess;
    }

    bless $self, $class;
}

=head2 error(filename, message)

=head2 warning

=head2 message

=head2 debug

Use these constructors to create the appropriate type of message.

=cut

sub error {
    return _new(@_, "error");
}

sub warning {
    return _new(@_, "warning");
}

sub message {
    return _new(@_, "message");
}

sub debug {
    return _new(@_, "debug");
}

=head1 METHODS

=head2 id

Returns the numberic id, -1 by default but changed to the insertion
order by C<Chroniton::Messages>.

=cut

sub id {
    my $self = shift;
    return $self->{id};
}

=head2 set_id(id)

Sets the C<id> to id,

=cut

# called by Messages when add()ed so that events sort properly,
# even if Time::HiRes isn't available 
sub set_id {
    my ($self, $id) = @_;
    $self->{id} = $id;
}

=head2 string([verbose?, suppress_progname?])

Stringifies the message for printing to a terminal.  use YAML or
Data::Dumper to prevent loss of information if saving to a file.

If verbose is true, extra information is printed.  If
suppress_progname is true, C<$0> is not printed before each line.

=cut

sub string {
    my $mess			 = shift;
    my $verbose			 = shift; # print extra info
    my $suppress_progname	 = shift; # print the program name on each line (if false)

    my ($type, $message, $filename, $time) = 
      ($mess->{type}, $mess->{message}, $mess->{file}, $mess->{time});

    my $str;    
    $str .= "$time: "         if defined $time     && $verbose;
    $str .= "$type: "         if defined $type;
    $str .= "$filename: "     if defined $filename && $verbose;
    $str .= "$message "       if defined $message;
    return $suppress_progname ? $str : "$0: $str";
}

1;
