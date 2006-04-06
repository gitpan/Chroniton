#!/usr/bin/perl
# Copyright (c) 2006 Jonathan Rockway

use inc::Module::Install;

name	       ('Chroniton');
abstract       ('Chroniton workstation backup system');
author	       ('Jonathan Rockway <jrockway@cpan.org>');
include	       ('ExtUtils::AutoInstall');
version_from   ('lib/Chroniton.pm');

license	       ('gpl');
install_script ('bin/chroniton.pl');

requires       ('Getopt::Euclid');
requires       ('File::Spec::Functions');
requires       ('constant');
requires       ('DateTime');
requires       ('base');
requires       ('File::HomeDir');
requires       ('YAML');
requires       ('Carp');
requires       ('Lingua::EN::Inflect');
requires       ('Number::Bytes::Human');
requires       ('Time::HiRes');
requires       ('File::Copy');
requires       ('Exporter');
build_requires ('Test::More');
build_requires ('Test::Strict');
build_requires ('Test::Pod::Coverage');
build_requires ('Test::MockObject');
build_requires ('File::Slurp');
build_requires ('Archive::Extract');

auto_install();
&WriteAll;
