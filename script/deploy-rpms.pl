#!/usr/bin/perl -w

use strict;
use warnings;

$|++;

use Cwd qw(abs_path);
use File::Basename;
use File::ShareDir qw(:ALL);
use File::Slurp;
use File::Spec;
use Getopt::Long qw(:config gnu_getopt);
use version;

use OpenNMS::Util;
use OpenNMS::Release;
use OpenNMS::Release::RPMPackage 2.6.7;

use vars qw(
	$SCRIPTDIR
	$YUMDIR
	$NOTAR

	$CMD_BUILDTOOL
	$CMD_UPDATE_SF_REPO
	$CMD_UPDATE_REPO
	$CMD_GENERATE

	$BRANCH_NAME
	$BRANCH_NAME_SCRUBBED
	$RELEASE
	$PASSWORD

	$FILE_SOURCE_TARBALL
	@FILES_RPMS
	$FILE_NIGHTLY
);

print $0 . ' ' . version->new($OpenNMS::Release::VERSION) . "\n";

$SCRIPTDIR   = abs_path(dirname($0));
$YUMDIR      = "/var/www/sites/opennms.org/site/yum";
$NOTAR       = 0;
$BRANCH_NAME = $ENV{'bamboo_OPENNMS_BRANCH_NAME'} || $ENV{'bamboo_planRepository_branchName'};

my $result = GetOptions(
	"y|yumdir=s"  => \$YUMDIR,
	"n|notar"     => \$NOTAR,
	"r|release=s" => \$RELEASE,
	"b|branch=s"  => \$BRANCH_NAME,
);

die "$YUMDIR does not exist!" unless (-d $YUMDIR);

$CMD_UPDATE_SF_REPO = File::Spec->catfile($SCRIPTDIR, 'update-sourceforge-repo.pl');
$CMD_UPDATE_REPO    = File::Spec->catfile($SCRIPTDIR, 'update-yum-repo.pl');
$CMD_GENERATE       = File::Spec->catfile($SCRIPTDIR, 'generate-yum-repo-html.pl');

my $passfile = File::Spec->catfile($ENV{'HOME'}, '.signingpass');
if (-e $passfile) {
	chomp($PASSWORD = read_file($passfile));
} else {
	print STDERR "WARNING: $passfile does not exist!  New RPMs will not be signed!\n";
}

opendir(FILES, '.') or die "Unable to read current directory: $!";
while (my $line = readdir(FILES)) {
	next if ($line =~ /^\.\.?$/);
	chomp($line);
	if ($line =~ /^opennms-source-.*\.tar.gz$/) {
		$FILE_SOURCE_TARBALL = $line;
	} elsif ($line =~ /\.rpm$/) {
		push(@FILES_RPMS, $line);
	} else {
		print STDERR "WARNING: unmatched file: $line\n";
	}
}
closedir(FILES) or die "Unable to close current directory: $!";

if ($NOTAR) {
	print STDERR "WARNING: skipping tarball deployment\n";
} else {
	open(TAR, "tar -tzf $FILE_SOURCE_TARBALL |") or die "Unable to run tar: $!";
	while (<TAR>) {
		chomp($_);
		if (/\/\.nightly$/) {
			$FILE_NIGHTLY = $_;
			last;
		}
	}
	close(TAR);
	die "Unable to find .nightly file in $FILE_SOURCE_TARBALL" unless (defined $FILE_NIGHTLY and $FILE_NIGHTLY ne "");
	chomp($RELEASE=`tar -xzf $FILE_SOURCE_TARBALL -O $FILE_NIGHTLY`);
	if ($RELEASE =~ /^repo:\s*(.*?)\s*$/) {
		$RELEASE = $1;
	} else {
		die "Unable to determine the appropriate release repository from '$RELEASE'";
	}
}

if (exists $ENV{'bamboo_OPENNMS_SOURCE_REPO'} and $ENV{'bamboo_OPENNMS_SOURCE_REPO'} ne "") {
	$RELEASE=$ENV{'bamboo_OPENNMS_SOURCE_REPO'};
}

if (not defined $RELEASE) {
	die "Unable to determine release.  Please make sure you have a source tarball with a .nightly file, or have defined --release= on the command-line.";
}

if (exists $ENV{'bamboo_OPENNMS_BRANCH_NAME'} and $ENV{'bamboo_OPENNMS_BRANCH_NAME'} ne "") {
	$BRANCH_NAME=$ENV{'bamboo_OPENNMS_BRANCH_NAME'};
}

if (not defined $BRANCH_NAME) {
	my $branch_text = `rpm -qip "$FILES_RPMS[0]"`;
	($BRANCH_NAME) = $branch_text =~ /This is an OpenNMS build from the (.*?) branch/mg;
}

if (not defined $BRANCH_NAME) {
	die "Unable to determine branch name from RPM.  Please specify --branch= on the command-line to set manually.";
}

$BRANCH_NAME_SCRUBBED = $BRANCH_NAME;
$BRANCH_NAME_SCRUBBED =~ s/[^[:alnum:]\.]+/\-/g;
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

for my $file (@FILES_RPMS) {
	print "- signing $file... ";
	my $package = OpenNMS::Release::RPMPackage->new(abs_path($file));
	$package->sign('opennms@opennms.org', $PASSWORD);
	print "done\n";
}

#print STDOUT "- uploading $FILE_SOURCE_TARBALL to the $BRANCH_NAME directory on SourceForge:\n";
#system($CMD_UPDATE_SF_REPO, $BRANCH_NAME, $FILE_SOURCE_TARBALL) == 0 or die "Failed to push $FILE_SOURCE_TARBALL to SourceForge: $!";

print STDOUT "- adding RPMs for $BRANCH_NAME to the YUM repo, based on $RELEASE:\n";
system($CMD_UPDATE_REPO, '-s', $PASSWORD, '-b', $BRANCH_NAME_SCRUBBED, $YUMDIR, $RELEASE, "common", "opennms", @FILES_RPMS) == 0 or die "Failed to update repository: $!";

print STDOUT "- updating repo RPMs for $BRANCH_NAME if necessary:\n";
my $platforms = read_properties(dist_file('OpenNMS-Release', 'platform.properties'));
my @platform_order = split(/\s*,\s*/, $platforms->{order_display});
delete $platforms->{order_display};
for my $platform (@platform_order) {
	next if ($platform eq 'common');
	my $reporpm = "opennms-repo-branches-${BRANCH_NAME_SCRUBBED}-${platform}.noarch.rpm";
	my $repodir = File::Spec->catdir($YUMDIR, 'repofiles');
	print "  * ${reporpm}... ";
	if (-e File::Spec->catfile($repodir, $reporpm)) {
		print "exists\n";
	} else {
		print "creating:\n";
		my @command = ("create-repo-rpm.pl", "-s", $PASSWORD, "-b", $YUMDIR, $BRANCH_NAME, $platform);
		print "@command\n";
		system(@command) == 0 or die "Failed to create repo RPM: $!\n";
	}
}

print STDOUT "- generating YUM HTML index:\n";
system($CMD_GENERATE, $YUMDIR) == 0 or die "Failed to generate YUM HTML: $!";

exit 0;
