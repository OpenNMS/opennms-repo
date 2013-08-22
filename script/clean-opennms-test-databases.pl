#!/usr/bin/perl -w

use strict;
use warnings;

use IO::Handle;

use vars qw(
	$PSQL
);

if (-x '/sw/bin/pgsql.sh') {
	print STDOUT "- resetting PostgreSQL:\n";
	system('/sw/bin/pgsql.sh', 'stop');
	sleep(5);
	system('/sw/bin/pgsql.sh', 'start');
	sleep(5);
	$PSQL = '/sw/bin/psql';
}

if (-x '/etc/init.d/postgresql') {
	print STDOUT "- resetting PostgreSQL:\n";
	system('/etc/init.d/postgresql', 'restart');
	sleep(5);
	$PSQL = '/usr/bin/psql';
}

if (not defined $PSQL) {
	print STDERR "Not sure what system this is, going to skip messing with PostgreSQL.\n";
	exit(0);
}

my $handle = IO::Handle->new();

my @databases = qw();

open($handle, '-|', "$PSQL -U opennms -l -t") or die "Unable to run $PSQL: $!\n";
while (my $line = <$handle>) {
	if ($line =~ /^\s*(opennms_test_.*?)\s*\|/) {
		push(@databases, $1);
	}
}
close($handle);

for my $database (@databases) {
	print STDOUT "- deleting $database... ";
	system($PSQL, '-U', 'opennms', '-c', "DROP DATABASE $database;") == 0 or die "Failed to drop $database: $!\n";
}

exit(0);
