#!/usr/bin/perl -w

use strict;
use warnings;

$|++;

use Cwd qw(abs_path);
use File::Basename;
use File::Slurp;
use File::Spec;
use version;

use OpenNMS::Release;

use vars qw(
	$SCRIPTDIR
	$APTDIR

	$CMD_BUILDTOOL
	$CMD_UPDATE_REPO

	$BRANCH_NAME
	$BRANCH_NAME_SCRUBBED
	$RELEASE
	$PASSWORD

	@FILES_DEBS
	$FILE_NIGHTLY
);

print $0 . version->new($OpenNMS::Release::VERSION) . "\n";

$SCRIPTDIR = abs_path(dirname($0));
$APTDIR    = "/var/ftp/pub/releases/opennms/debian";

die "$APTDIR does not exist!" unless (-d $APTDIR);

$CMD_UPDATE_REPO = File::Spec->catfile($SCRIPTDIR, 'update-apt-repo.pl');

my $passfile = File::Spec->catfile($ENV{'HOME'}, '.signingpass');
if (-e $passfile) {
	chomp($PASSWORD = read_file($passfile));
} else {
	print STDERR "WARNING: $passfile does not exist!  New RPMs will not be signed!";
}

opendir(FILES, '.') or die "Unable to read current directory: $!";
while (my $line = readdir(FILES)) {
	next if ($line =~ /^\.\.?$/);
	chomp($line);
	if ($line =~ /\.deb$/) {
		push(@FILES_DEBS, $line);
	} else {
		print STDERR "WARNING: unmatched file: $line\n";
	}
}
closedir(FILES) or die "Unable to close current directory: $!";

my $repo_file = '.nightly';
if (-e 'opennms-build-repo.txt') {
	$repo_file = 'opennms-build-repo.txt';
}

if (-e $repo_file) {
	chomp($RELEASE=read_file($repo_file));
	if ($RELEASE =~ /^repo:\s*(.*?)\s*$/) {
		$RELEASE = $1;
	} else {
		die "Repo file $repo_file exists, but unable to determine the appropriate release repository from '$RELEASE'";
	}
} else {
	print STDERR "WARNING: using 'unstable' as the source release";
	$RELEASE='unstable';
}

chomp($BRANCH_NAME = read_file('opennms-build-branch.txt'));
$BRANCH_NAME_SCRUBBED = $BRANCH_NAME;
$BRANCH_NAME_SCRUBBED =~ s/[^[:alnum:]\.]+/\-/g;
$BRANCH_NAME_SCRUBBED =~ s/\-*$//g;

print STDOUT <<END;
==============
Deploying DEBs
==============

APT Directory:     $APTDIR
Release:           $RELEASE
Branch:            $BRANCH_NAME
Branch (scrubbed): $BRANCH_NAME_SCRUBBED

END

print STDOUT "- adding DEBs for $BRANCH_NAME to the APT repo, based on $RELEASE:\n";
print "$CMD_UPDATE_REPO -s XXXXX -b '$BRANCH_NAME_SCRUBBED' '$APTDIR' '$RELEASE' @FILES_DEBS\n";
system($CMD_UPDATE_REPO, '-s', $PASSWORD, '-b', $BRANCH_NAME_SCRUBBED, $APTDIR, $RELEASE, @FILES_DEBS) == 0 or die "Failed to update repository: $!";

exit 0;
