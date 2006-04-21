#!/usr/bin/perl
# Copyright (c) 2006 Jonathan Rockway

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
requires	      ('DateTime');
requires	      ('Exporter');
requires	      ('File::Copy');
requires	      ('File::HomeDir');
requires	      ('File::Spec::Functions');
requires	      ('File::Stat::ModeString');
requires	      ('Getopt::Euclid');
requires              ('IO::Zlib');
requires	      ('Lingua::EN::Inflect');
requires	      ('Number::Bytes::Human');
requires	      ('Time::Duration');
requires	      ('Time::HiRes');
requires	      ('YAML::Syck');
build_requires	      ('Test::More');
build_requires	      ('Test::Strict');
build_requires	      ('Test::Pod::Coverage');
build_requires        ('Test::Pod');
build_requires	      ('Test::MockObject');
build_requires	      ('File::Slurp');
build_requires        ('File::Temp');


requires_external_bin ('tar');
requires_external_bin ('gzip');
requires_external_bin ('rm');

auto_install();
&WriteAll;
