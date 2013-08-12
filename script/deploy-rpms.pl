#!/usr/bin/perl -w

use strict;
use warnings;

$|++;

use Cwd qw(abs_path);
use File::Basename;
use File::Slurp;
use File::Spec;

use vars qw(
	$SCRIPTDIR
	$YUMDIR

	$CMD_BUILDTOOL
	$CMD_UPDATE_SF_REPO
	$CMD_UPDATE_REPO
	$CMD_GENERATE

	$TIMESTAMP
	$REVISION
	$BRANCH_NAME
	$BRANCH_NAME_SCRUBBED
	$RELEASE
	$PASSWORD

	$FILE_SOURCE_TARBALL
	@FILES_RPMS
	$FILE_NIGHTLY
);

$SCRIPTDIR = abs_path(dirname($0));
$YUMDIR    = "/var/www/sites/opennms.org/site/yum";

die "$YUMDIR does not exist!" unless (-d $YUMDIR);

$CMD_BUILDTOOL      = File::Spec->catfile($SCRIPTDIR, 'buildtool.pl');
$CMD_UPDATE_SF_REPO = File::Spec->catfile($SCRIPTDIR, 'update-sourceforge-repo.pl');
$CMD_UPDATE_REPO    = File::Spec->catfile($SCRIPTDIR, 'update-yum-repo.pl');
$CMD_GENERATE       = File::Spec->catfile($SCRIPTDIR, 'generate-yum-repo-html.pl');

chomp($TIMESTAMP = `$CMD_BUILDTOOL nightly-rpm get_stamp`);
chomp($REVISION  = `$CMD_BUILDTOOL nightly-rpm get_revision`);

my $passfile = File::Spec->catfile($ENV{'HOME'}, '.signingpass');
if (-e $passfile) {
	$PASSWORD = read_file($passfile);
} else {
	print STDERR "WARNING: $passfile does not exist!  New RPMs will not be signed!";
}

opendir(FILES, '.') or die "Unable to read current directory: $!";
while (<FILES>) {
	chomp($_);
	if (/^opennms-source-.*\.tar.gz$/) {
		$FILE_SOURCE_TARBALL = $_;
	} elsif (/\.rpm$/) {
		push(@FILES_RPMS, $_);
	}
}
closedir(FILES) or die "Unable to close current directory: $!";

open(TAR, "tar -tzf $FILE_SOURCE_TARBALL |") or die "Unable to run tar: $!";
while (<TAR>) {
	chomp($_);
	if (/\/\.nightly$/) {
		$FILE_NIGHTLY = $_;
		last;
	}
}
close(TAR) or die "Unable to close tar: $!";

die "Unable to find .nightly file in $FILE_SOURCE_TARBALL" unless (defined $FILE_NIGHTLY and $FILE_NIGHTLY ne "");

chomp($RELEASE=`tar -xzf $FILE_SOURCE_TARBALL -O $FILE_NIGHTLY`);

if ($RELEASE =~ /^repo:\s*(.*?)\s*$/) {
	$RELEASE = $1;
} else {
	die "Unable to determine the appropriate release repository from '$RELEASE'";
}

my $branch_text = `rpm -qip "$FILES_RPMS[0]"`;
($BRANCH_NAME) = $branch_text =~ /This is an OpenNMS build from the (.*?) branch/mg;
$BRANCH_NAME_SCRUBBED = $BRANCH_NAME;
$BRANCH_NAME_SCRUBBED =~ s/[^[:alnum:]]+/\-/g;
$BRANCH_NAME_SCRUBBED =~ s/\-*$//g;

print STDOUT <<END;
==============
Deploying RPMs
==============

YUM Directory:     $YUMDIR
Release:           $RELEASE
Branch:            $BRANCH_NAME
Branch (scrubbed): $BRANCH_NAME_SCRUBBED

END

system($CMD_UPDATE_SF_REPO, $BRANCH_NAME, $FILE_SOURCE_TARBALL) == 0 or die "Failed to push $FILE_SOURCE_TARBALL to SourceForge: $!";
system($CMD_UPDATE_REPO, '-s', $PASSWORD, '-b', $BRANCH_NAME_SCRUBBED, $YUMDIR, $RELEASE, "common", "opennms", @FILES_RPMS) == 0 or die "Failed to update repository: $!";
system($CMD_GENERATE, $YUMDIR) == 0 or die "Failed to generate YUM HTML: $!";

exit 0;
