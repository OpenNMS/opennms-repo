#!/usr/bin/perl -w

$|++;

use strict;
use warnings;

use Cwd;
use Data::Dumper;
use File::Basename;
use Git;
use IO::Handle;

use OpenNMS::Util;

use vars qw(
	$TIMESTAMPFILE
	$REVISIONFILE
	$GITHASHFILE

	$PROJECT
	$COMMAND
	$BRANCH

	$GIT
	$GITDIR
);

sub usage() {
	print STDERR <<END;
usage: $0 <project_name> <command>

available commands:
	get              Get the latest build ID (format: 0.<timestamp>.<revision>)
	get_stamp        Get the latest build timestamp
	get_revision     Get the latest build revision
	has_hash_changed Return 0 (true) if git has been modified since last save, 1 if not.
	save             Save the current build ID state

END
	exit 1;
}

sub get_branch_name() {
	my $ret = $GIT->command_oneline('name-rev', 'HEAD');
	if ($ret =~ /^HEAD\s+(.*)\s*$/) {
		my $name = $1;
		if ($name =~ /tags\/[^-]*-([[:alnum:]\.]+)/) {
			return $1;
		} else {
			$name =~ s/[^[:alnum:]]+/-/g;
			return $name;
		}
	} else {
		return undef;
	}
}

sub get_stored_value($) {
	my $file = shift;

	return 0 unless (-e $file);

	my $value = slurp($file);
	chomp($value);

	return $value ne ""? $value : 0;
}

sub get_current_timestamp() {
	my ($ret) = $GIT->command('log', '--pretty=format:%cd', '--date=short', '-1');
	if ($ret =~ /^(?:Date:\s*)?(\d\d\d\d)\-(\d\d)\-(\d\d)\s*$/m) {
		return $1 . $2 . $3;
	} else {
		die "unable to determine current timestamp with command 'git log --pretty=format:\%cd --date=short -1'";
	}
}

sub get_current_revision() {
	my $stored_revision   = get_stored_value($REVISIONFILE);
	my $stored_timestamp  = get_stored_value($TIMESTAMPFILE);
	my $current_timestamp = get_current_timestamp();

	if ($stored_timestamp eq $current_timestamp) {
		return $stored_revision + 1;
	} else {
		return 1;
	}
}

sub get_current_githash() {
	my ($ret) = $GIT->command('show');
	($ret) = split(/\r?\n/, $ret);
	if ($ret =~ /^commit\s+(\S+)\s*$/m) {
		return $1;
	} else {
		die "unable to determine current git hash with command 'git show'";
	}
}

sub get_build_id() {
	return '0.' . get_current_timestamp() . '.' . get_current_revision();
}

sub has_hash_changed() {
	return 1 if (not -e $GITHASHFILE);

	my $stored = get_stored_value($GITHASHFILE);
	my $current = get_current_githash();

	return $stored ne $current;
}

sub update_file($$) {
	my $filename = shift;
	my $contents = shift;

	my $handle = IO::Handle->new();
	open($handle, '>' . $filename) or die "unable to write to $filename: $!";
	print $handle $contents;
	close($handle);
}

sub update_build_state() {
	update_file($TIMESTAMPFILE, get_current_timestamp());
	update_file($REVISIONFILE,  get_current_revision());
	update_file($GITHASHFILE,   get_current_githash());
}

$PROJECT = shift @ARGV;
$COMMAND = shift @ARGV;
$GITDIR  = shift @ARGV || Cwd::abs_path('.');
usage() unless (defined $COMMAND);

$GIT     = Git->repository( Directory => $GITDIR );

$BRANCH = get_branch_name();
die "Unable to determine branch!" unless (defined $BRANCH);

$TIMESTAMPFILE = "$ENV{HOME}/.buildtool-$PROJECT-$BRANCH-timestamp";
$REVISIONFILE  = "$ENV{HOME}/.buildtool-$PROJECT-$BRANCH-revision";
$GITHASHFILE   = "$ENV{HOME}/.buildtool-$PROJECT-$BRANCH-githash";

if ($COMMAND eq 'get') {
	print get_build_id(), "\n";
} elsif ($COMMAND eq 'get_stamp') {
	print get_current_timestamp(), "\n";
} elsif ($COMMAND eq 'get_revision') {
	print get_current_revision(), "\n";
} elsif ($COMMAND eq 'has_hash_changed') {
	exit (has_hash_changed()? 0 : 1);
} elsif ($COMMAND eq 'save') {
	update_build_state();
} else {
	print STDERR "unknown command: $COMMAND\n\n";
	usage();
}

exit 0;
