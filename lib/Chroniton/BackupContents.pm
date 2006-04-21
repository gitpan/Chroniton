#!/usr/bin/perl
# BackupContents.pm
# Copyright (c) 2006 Jonathan Rockway

package Chroniton::BackupContents;
use strict;
use warnings;
use Chroniton::File;

=head1 NAME

Chroniton::BackupContents - stores the contents of a backup set (file list and file metadata)

=head1 SYNOPSIS

     my $contents = Chroniton::BackupContents->new("/location/of/backup/set");
     $contents->add("/path/to/a/file")
     $contents->add("/path/to/another/file");
     my @files     = $contents->ls;
     my @revisions = $contents->get_file("/path/to/a/file");

=head1 METHODS

=head2 new($location)

Creates a new BackupContents object, that assumes added files will be
stored in C<$location>.

=cut

sub new {
    my ($class, $location) = @_;
    my $self = {location => $location, files => {}};
    return bless $self, $class;
}

=head2 add($path)

Adds C<path> to the backup set.  C<path> is the location of a real file
on the filesystem, the metadata object is created by inspecting this
file.

=cut
sub add {
    my ($self, $filename, $original) = @_;
    my $file = Chroniton::File->new($filename);
    $file->{location} = $self->{location};  
    $file->{target}   = $original if $original;
    $self->add_object($file);
}

=head2 add_object

Adds a C<File> object to the backup contents.

=cut

sub add_object {
    my ($self, $file) = @_;
    my $filename = $file->{name};
    my $versions = $self->{files}->{$filename};
    if(ref $versions){
	push @$versions, $file;
    }
    else {
	$versions = [$file];
    }
    
    $self->{files}->{$filename} = $versions;
    return;
   
}

=head2 ls

Lists all files in the backup.

=cut

sub ls {
    return keys %{$_[0]->{files}};
}

=head2 get_file(filename)

Gets the C<Chroniton::File> objects corresponding to C<filename>.

=cut

sub get_file {
    my ($self, $filename) = @_;
    return if !defined $filename;
    my $ref = $self->{files}->{$filename};
    return @$ref if $ref;
    return; # nothing otherwise
}

=head2 location

Returns the location of this backup

=cut

sub location {
    return $_[0]->{location};
}

1;
