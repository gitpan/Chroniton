#!/usr/bin/perl
# File.pm
# Copyright (c) 2006 Jonathan Rockway

package Chroniton::File;
use strict;
use warnings;
use Chroniton::Messages;
use File::Stat::ModeString;
use Carp;
use Digest::MD5;

=head1 NAME

Chroniton::File - represents a file in a the backup set

=head1 SYNOPSIS

     my $file = Chroniton::File->new("/path/to/file");

=head1 METHODS

=head2 new(original)

Creates an instance, gleaning file metadata from C<original>.

=cut

sub new {
    my $class = shift;
    my ($original) = @_;
    
    my $self = {};
    $self->{name} = $original;
    
    my $md5;
    if(-f $original && !-l $original){
	my $dgst = Digest::MD5->new;
	open(my $FILE, "<", $original) or croak "cannot read $original: $!";
	$dgst->addfile($FILE);
	$md5 = $dgst->hexdigest;
    }
    
    $self->{type} = "file";
    $self->{type} = "directory" if -d $original;
    $self->{type} = "link" if -l $original;

    if(-l $original){
	lstat $original or croak "could not stat $original: $!";
    }
    else {
	stat $original or croak "could not stat $original: $!";
    }

    $self->{metadata} = {
			 md5         => $md5,
			 permissions => mode_to_string((stat _)[2]),
			 uid         => scalar getpwuid((stat _)[4]),
			 gid         => scalar getgrgid((stat _)[5]),
			 mtime       => (stat _)[9],
			 ctime       => (stat _)[10],
			 atime       => (stat _)[8],
			 size        => (stat _)[7],
			};
    #TODO: extended filesystem attributes
    
    return bless $self, $class;
}

=head2 metadata

Returns the metadata associated with this file as a hashref.

Valid metadata is: permissions (as a string, like -rwxr-xr-x), owner
user name, owner group name, mtime, atime, ctime (all in seconds past
the epoch), and size (in bytes).

=cut

sub metadata {
    my $self = shift;
    return $self->{metadata};
}

=head2 apply_metadata(file, log)

Applies the metadata contained in this object to an actual C<file> on
the filesystem.  If C<log> is specified, logs messages to a
C<Chroniton::Messages> object.

=cut

sub apply_metadata {
    my ($self, $to, $log) = @_;
    my $metadata_ref = $self->metadata;
    $log = Chroniton::Messages->new if(!$log);
    $log->debug($to, "restoring saved metadata onto $to");
    
    my $permissions = $metadata_ref->{permissions} || "-rw-r--r--"; # use a sane default
    my $n_permissions = string_to_mode($permissions);
    $log->debug($to, "setting $permissions ($n_permissions) on $to");
    chmod($n_permissions, $to)
      or $log->warning($to, "couldn't set permissions $permissions on $to");
    
    my $user  = $metadata_ref->{uid};
    my $uid   = getpwnam($user)  || -1;
    my $group = $metadata_ref->{gid};
    my $gid   = getgrnam($group) || -1;

    chown $uid, $gid, $to
      or $log->warning($to, "couldn't set ownership $uid:$gid ".
		            "($user:$group) on $to");

    my $mtime = $metadata_ref->{mtime} || undef; 
    my $atime = $metadata_ref->{atime} || undef;
    
    utime $atime, $mtime, $to
      or $log->warning($to, "could not set access or modification".
		            " times on $to: $!");

    # finally, check the md5sum
    my $orig_md5 = $metadata_ref->{md5};
    if($orig_md5){
	my $sum;
	eval {
	    my $md5 = Digest::MD5->new;
	    open (my $FH, "<", $to) or die "$!";
	    $md5->addfile($FH);
	    $sum = $md5->hexdigest;
	};	
	if($@){
	    $log->warning($to, "problem checking md5sum on $to: $@");
	}

	if($orig_md5 ne $sum){
	    $log->warning($to, "md5sum did not match -- backup is corrupt!");
	}
    }
    else {
	# only warn about this on regualar files
	if($metadata_ref->{permissions} =~ /^-/){
	    $log->warning($to, "no md5sum in database, data ".
		               "integrity not assured!"); 
	}
    }
    return;
}


1; # ok
