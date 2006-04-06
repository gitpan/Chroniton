#!/usr/bin/perl
# Messages.pm - [description]
# Copyright (c) 2006 Jonathan Rockway

package Chroniton::Messages;
use strict;
use warnings;
use Chroniton::Message;
use YAML qw(DumpFile);
use Lingua::EN::Inflect qw(NO);
use Number::Bytes::Human qw(format_bytes);
use File::HomeDir;
use Carp;

=head1 NAME

Chroniton::Messages - an event log for Chroniton

=head1 SYNOPSIS

     my $log = Chroniton::Messages->new(\*STDERR);

     $log->message("/etc", "starting backup of /etc");
     $log->debug("/etc", "descending into /etc");
     $log->warning("/etc/shadow", "can't read /etc/shadow");
     $log->error("foo", "can't backup foo: doesn't exist");
   
     $log->add(Chroniton::Event-> ... );

     my @errors  = $log->retrieve("error");
     my @logfile = $log->retrieve_all;

=head1 METHODS

=head2 new([print])

Creates an instance.  Argument print is a reference to a filehandle to
write each message to.  If none is specified, messages are stored
only.

=cut

sub new {
    my $class = shift;
    my $print = shift;
    my $self = { error => [],
		 warning => [],
		 message => [],
		 event => [],
		 internal => { 
			      print => $print,
			      count => 0,

			      # # # helpful when debugging log dumps # # #
			      pid   => $$,
			      name  => $0,
			      uid   => $<,
			      euid  => $>,
			      gid   => $(,
			      egid  => $),
			      perl  => $^V,
			      os    => $^O,
			     },
	       };
    
    bless $self, $class;
}

=head2 add(message)

Adds a C<Chroniton::Message> object to the log.  Dies if the message
isn't actually a message (i.e. can't set ID or query type).

=cut

sub add {
    my $self = shift;
    my $mess = shift;

    my $type = $mess->{type};
    confess "message ($mess) is invalid\n". Dump($mess) 
      if !$type || $type eq "internal";
    
    $self->{internal}->{count}++;
    $mess->set_id($self->{internal}->{count});
    
    if($self->{internal}->{print}){

	print {$self->{internal}->{print}} $mess->string. "\n";
    }
    
    push @{$self->{$type}}, $mess;
}

=head2 retrieve_all

Returns a list of all messages, sorted by their insertion order.

=head2 retrieve([type])

Returns a list of all messages of type C<type>, not sorted.

=cut

sub retrieve_all {
    my $self = shift;
    my @result;
    return $self->{internal}->{count} if !wantarray;

    foreach (keys %$self){
	next if $_ eq "internal";
	push @result, @{$self->{$_}};
    }
    
    return sort _sort @result; 
}

sub retrieve {
    my $self = shift;
    my $type = shift;
    my $message_ref = $self->{$type};
    return unless defined $message_ref;

    return @$message_ref; # doesn't sort, since i never need sorted data
}

=head2 error

=head2 warning

=head2 message

=head2 debug

Adds the respective type of message to the database.
L<Chroniton::Message> for the argument ordering, as these methods
merely serve as a convenient way to write:

   $log->add(Chroniton::Message->type(@_));

=cut

sub error {
    my $self = shift;
    $self->add(Chroniton::Message->error(@_));
}

sub warning {
    my $self = shift;
    $self->add(Chroniton::Message->warning(@_));
}

sub message {
    my $self = shift;
    $self->add(Chroniton::Message->message(@_));
}

sub debug {
    my $self = shift;
    $self->add(Chroniton::Message->debug(@_));
}

=head2 summary

Returns a string summarizing the event log.

=cut

sub summary {
    my $self = shift;
    my $errors = $self->retrieve("error");
    my $warnings = $self->retrieve("warning");
    my @events = $self->retrieve("event");
    my ($dir, $copy, $link, $delete, $unknown) = (0, 0, 0, 0, 0);
    my ($bytes, $ctime) = (0, 1e-30);
    foreach my $event (@events){
	my $id = $event->{event_id};
	if($id == 10){
	    $copy++;
	    $bytes += $event->{bytes};
	    $ctime += $event->{elapsed_time};
	}

	$link++    if $id == 11;
	$delete++  if $id == 12;
	$dir++     if $id == 13;
	$unknown++ if $id < 10 || $id > 13;
    }

    my $result = NO("error", $errors). ", ". NO("warning", $warnings). ".\n";
    $result .= NO("  file", $copy). " copied.\n";
    $result .= NO("  directory", $dir). " created.\n";
    $result .= NO("  link", $link). " created.\n";
    $result .= NO("  stale file", $delete). " deleted.\n";
    $result .= NO("  unknown event", $unknown). ".\n";

    if($copy > 0){
	my $rate = format_bytes($bytes/$ctime, si => 1);
	my $b    = format_bytes($bytes, si => 1);
	$result .= "$b copied in $ctime seconds ($rate/s)\n";
    }
    
    return $result;
}

=head2 fatal(message, filename)

Logs an error, saves the logfile, and then dies (via C<confess>),
printing the error message to STDERR and all log entries to STDOUT.

=cut

sub fatal {
    my $log      = shift;
    my $message  = shift;
    my $filename = shift;
    $log->error($filename, $message);

    my $loc;
    eval {
	$loc = File::HomeDir->my_home();
    };
    if(!defined $loc || !-d $loc){
	$log->warning($loc, "cannot write to homedir!");
	$loc = "/tmp";
    }
    
    $log->message($loc, "dumping log file to $loc");
    
    $loc .= "/BACKUP_ERRORS<". time(). ">.log.yml";
    eval {
	DumpFile($loc, $log);
    };
    if($@){
	$log->warning($loc, "sorry, couldn't write the logfile!");
    }

    if(!$log->{internal}->{print}){
	map {print $_->string. "\n"} $log->retrieve_all;
    }

    confess "$0: fatal error: $message\n *** Stop.";
}

sub _sort {
    return $a->id <=> $b->id;
}

1;
