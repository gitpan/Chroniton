package Chroniton::Config::Test;
use base qw(Chroniton::Config);

sub config_file {
    return "/tmp/config.$$.yml";
}
sub _blank_config {
    return { storage_directory => "/tmp",
	     backup_locations => [qw(/tmp)], }
}

1;

package main;
use Test::More tests=>14;
use Chroniton::Messages;
use Chroniton::Config;
use Chroniton::State;

my $config = Chroniton::Config->new;
my $log    = Chroniton::Messages->new;

# this might die if your real configuration is messed up
ok($config, "create real config"); #1
ok($config->config_file, "config is stored somewhere"); #2
ok(scalar $config->locations, "some backup locations"); #3
ok($config->destination, "somewhere to backup to"); #4
ok($config->archive_after =~ /^[0-9]+$/, "archive_after is a number");#5
undef $config;

ok(ref Chroniton::Config::_blank_config, "blank config returns something"); #6
is(Chroniton::Config::Test::config_file, "/tmp/config.$$.yml", "fake config works"); #7

eval {
    $config = Chroniton::Config::Test->new;
}; # fails the first time

$config = Chroniton::Config::Test->new;
ok(-e("/tmp/config.$$.yml"), "fake config file created"); #8
ok(mkdir("/tmp/test.$$"), "make some place for the fake state to live"); #9
$config->{storage_directory} = "/tmp/test.$$";
$config->{backup_locations}  = [qw(foo bar)];
is_deeply([$config->locations], [qw(foo bar)], "fake config stuck"); #10

# now test state
my $state = Chroniton::State->new($config, $log);
ok($state, "state worked"); #11
$state->{foo_bar} = "foo bar";
$state->save;
undef $state;

# bring it back in, with the "foo bar" bit
$state = Chroniton::State->new($config, $log);
is($state->{foo_bar}, "foo bar", "state persists?"); #12
undef $state;

# corrupt the statefile
unlink "/tmp/test.$$/state.yml";
open(my $sf, ">/tmp/test.$$/state.yml");
print {$sf} "           this file has been corrupted!";
close $sf;
$state = Chroniton::State->new($config, $log);
# TODO: really rebuild, not just blank
is($state->{foo_bar}, undef, "corrupted state file rebuilt"); #13

unlink "/tmp/test.$$/state.yml";
rmdir "/tmp/test.$$";

eval {
    $state = Chroniton::State->new($config, $log);
};
ok($@, "state shouldn't load if there's nowhere to put it"); #14

mkdir "/tmp/test.$$"; # so cleanup doesn't generate YAML errors

# done.

END {
    # cleanup
    eval {
	unlink "/tmp/config.$$.yml";
	unlink "/tmp/test.$$/state.yml";
	rmdir "/tmp/test.$$";
    };
}
