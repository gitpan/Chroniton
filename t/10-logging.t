#!/usr/bin/perl
# 10-logging.t
# Copyright (c) 2006 Jonathan Rockway

use Test::More tests=>28;
use Chroniton::Messages;
use Chroniton::Message;
use Chroniton::Event;
use YAML;

my $log = new Chroniton::Messages();

eval {
    $log->add(undef);
};
ok($@, "bad data should be rejected"); # 1

$log->error("foo", "foo error");
$log->error("foo", "foo error 2");
$log->warning("bar", "bar warning");
$log->warning("bar", "bar warning 2");
$log->warning("bar", "bar warning 3");
$log->message("baz", "baz message");

is(scalar $log->retrieve_all, 6, "number of messages added"); # 2
is(scalar $log->retrieve("error"), 2, "errors added");        # 3
is(scalar $log->retrieve("warning"), 3, "warnings added");    # 4
is(scalar $log->retrieve("message"), 1, "messages added");    # 5
is(scalar $log->retrieve("event"), 0, "events added");        # 6

my @r = map {[$_->id, $_->{type}]} $log->retrieve_all;

is_deeply([@r], [[1, "error"],
		 [2, "error"],
		 [3, "warning"],
		 [4, "warning"],
		 [5, "warning"],
		 [6, "message"]],
	  "message counter and types");                       # 7

@r = map {[$_->id, $_->{type}]} $log->retrieve("message");
is_deeply([@r], [[6, "message"]], 
	  "counter and type, filtered on messaes"); # 8

@r = $log->retrieve("made_up_name");
is(scalar @r, 0, "empty set");  # 9

## test all the events [Chroniton::Event]s

$log->add(Chroniton::Event->event("file", "elite user logged in", 1337));
$log->add(Chroniton::Event->copy("/etc/passwd", "/hacker/stash", 3.1337, 42));
$log->add(Chroniton::Event->link("source", "destination"));
$log->add(Chroniton::Event->delete("/etc/passwd"));
$log->add(Chroniton::Event->mkdir("/EXPLOITED")); # yeah, it's late at night.

@r = $log->retrieve("event");
is(scalar @r, 5, "5 events added?"); # 10

ok($log->summary, "summary doesn't die"); # 11

eval {
    $log->fatal("foo bar");
};
ok(defined $@, "fatal dies"); # 12

undef $log;

# make a new log, to test printing and logs without copies
open NULL, ">/dev/null";
$log = Chroniton::Messages->new(\*NULL);
ok($log, "log creation ok"); # 13
$log->debug("foo", "bar");
my $event = Chroniton::Event->event("bar", "baz", -12, 87);
eval {
    $log->add($event);
};
ok(!$@, "adding event of type -12 works"); # 14
ok($log->retrieve("event"), "adding/getting new type of event"); # 15
ok($log->summary); # 16
eval {
    $log->add("die");
};
ok($@, "adding invalid entry failed"); # 17
eval {
    $log->retrieve("internal");
};
ok($@, "retrieving internal data failed"); # 18
my $r = $log->retrieve("foo bar i made this up");
ok(!$r, "retrieving fake category failed"); # 19

# do some corner-cases tests of message objects
my ($filename, $message) = qw(foo bar);
my $bad_message = Chroniton::Message->_new;
ok(!defined $bad_message->string(undef, 1), "nothing, since the message is blank"); #20

my $mess = Chroniton::Message->message($filename, $message);
is($mess->string(1) =~ tr/:/:/, 4); #21
$mess = Chroniton::Message->message($filename, "");
like($mess->string, qr/:\s+$/); #22
$mess = Chroniton::Message->message("", $message);
like($mess->string, qr/message: bar/); #23
$mess = Chroniton::Message->message($filename, $message);
my $a = $mess->string;
#my $b = $mess->string(1);
delete $mess->{time};
delete $mess->{file};
my $c = $mess->string(1);
is($a, $c, "deleting time is the same as not printing it"); # 24
like($a, qr"^$0", "progname is printed");# 25
unlike($mess->string(undef, 1), qr"^$0", "progname suppressed");# 26

eval {
    $log->add(Chroniton::Message->_new("foo", "bar", "internal"));
};
ok($@, "adding internal event should fail"); #27

eval {
    $log->fatal("foo", "bar");
};
ok($@, "fatal events should be fatal even if internal->print is set"); #28

1;
