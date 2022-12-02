#!/usr/bin/env perl

use strict;
use warnings;

use Fcntl qw(LOCK_EX LOCK_NB);
use File::NFSLock qw(uncache);
use File::Spec;
use Getopt::Long qw(:config gnu_getopt);

use vars qw(
	$PATH

	$TIMEOUT
	$STALE_TIMEOUT

	@COMMAND
);

my $getopt = GetOptions(
	't|timeout=i' => \$TIMEOUT,
	's|stale-timeout=i' => \$STALE_TIMEOUT,
);

if (not defined $TIMEOUT or $TIMEOUT == 0) {
	$TIMEOUT = 30 * 60; # 30 minutes
}

if (not defined $STALE_TIMEOUT or $STALE_TIMEOUT == 0) {
	$STALE_TIMEOUT = $TIMEOUT + 10;
}

$PATH = shift @ARGV;

#print "path=$PATH\n";
#print "timeout=$TIMEOUT\n";
#print "stale_timeout=$STALE_TIMEOUT\n";
#print "command=@ARGV\n";

if (@ARGV == 0) {
	die "usage: $0 [-t timeout-in-seconds] [-s stale-timeout-in-seconds] </path/to/nfs-directory> command [arguments]\n";
}

if (defined $PATH and -d $PATH) {
	my $lockfile = File::Spec->catfile($PATH, '.exec-nfs-exclusive.lock');
	if (my $lock = File::NFSLock->new({
		file               => $lockfile,
		lock_type          => LOCK_EX, #| LOCK_NB,
		blocking_timeout   => $TIMEOUT,
		stale_lock_timeout => $STALE_TIMEOUT,
	})) {
		print STDERR "Running '@ARGV[0]' with an exclusive lock for up to $TIMEOUT seconds.\n";
		system(@ARGV) == 0 or die "Failed to run @ARGV: $!\n";
	} else {
		die "I couldn't lock $lockfile after $TIMEOUT seconds. $File::NFSLock::errstr\n";
	}
} else {
	print "'$PATH' is not a directory!\n";
	exit 1
}

