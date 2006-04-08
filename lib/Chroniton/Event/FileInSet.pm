#!/usr/bin/perl
# FileInSet.pm
# Copyright (c) 2006 Jonathan Rockway

package Chroniton::Event::FileInSet;
use strict;
use warnings;
use File::Stat::ModeString;
use base qw(Chroniton::Event);

=head1 NAME 

Chroniton::Event::FileInSet - represents a file (and its metadata)
that's in a backup set.

=head1 SYNOPSIS

     my $log = Chroniton::Messages->new;
     $log->add(Chroniton::Event::FileInSet->new("/path/to/file", "/backup/file");

=head1 CONSTRUCTORS

=head2 new(original, backed_up)

Takes two arguments, the original name of the file C<original>, and
the backup copy of the file C<backed_up>.

=cut

sub new {
    my $class = shift;
    my ($original, $backed_up) = @_;
    my $message;
    $message = "directory $original saved" if -d $original;
    $message = "file $original saved" if !-d $original;
    
    my $self = Chroniton::Event::event($class, $original, $message, 0);
    $self->{original} = $original;
    $self->{frozen}   = $backed_up;

    $self->{type} = "files"; # this differs from the others in that it has an s
    stat $original;
    $self->{metadata} = {
			 permissions => mode_to_string((stat _)[2]),
			 uid         => scalar getpwuid((stat _)[4]),
			 gid         => scalar getgrgid((stat _)[5]),
			 mtime       => (stat _)[9],
			 ctime       => (stat _)[10],
			 atime       => (stat _)[8],
			 size        => (stat _)[7],
			};
    return $self;
};

1;
