#!/usr/bin/perl
# Copyright (c) 2006 Jonathan Rockway

use strict;
use warnings;
use inc::Module::Install;

name		      ('Chroniton');
abstract	      ('Chroniton workstation backup system');
author		      ('Jonathan Rockway <jrockway@cpan.org>');
include		      ('ExtUtils::AutoInstall');
version_from	      ('lib/Chroniton.pm');

license		      ('gpl');
install_script	      ('bin/chroniton.pl');

requires	      ('base');
requires	      ('Carp');
requires	      ('constant');
requires              ('Archive::Extract');
requires              ('Archive::Tar');
requires	      ('Exporter');
requires	      ('File::Copy');
requires	      ('File::HomeDir');
requires	      ('File::Spec::Functions');
requires	      ('File::Stat::ModeString');
requires	      ('Getopt::Euclid');
requires              ('IO::Zlib');
requires	      ('Lingua::EN::Inflect');
requires	      ('Number::Bytes::Human');
requires              ('Text::Wrap');
requires	      ('Time::Duration');
requires	      ('Time::HiRes');
requires	      ('YAML::Syck');

features              ('Backup/Restore Extended Filesystem Attributes'
		         => [ 'File::ExtAttr' => '0.05' ]
		      );
		       

# for building
build_requires	      ('Test::More');
build_requires	      ('Test::Strict');
build_requires	      ('Test::Pod::Coverage');
build_requires        ('Test::Pod');
build_requires	      ('Test::MockObject');
build_requires	      ('File::Slurp');
build_requires        ('File::Temp');

# FIX THIS; not *really* required, but damn bad if you don't have them
requires_external_bin ('tar');
requires_external_bin ('gzip');
requires_external_bin ('rm');

auto_install();
&WriteAll;
