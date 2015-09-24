#!/usr/bin/perl -w

$|++;

use strict;
use warnings;

use Cwd;
use File::Basename;
use File::Copy;
use File::Path;
use File::ShareDir qw(:ALL);
use File::Spec;
use File::Temp qw(tempdir);
use Getopt::Long qw(:config gnu_getopt);
use IO::Handle;
use version;

use OpenNMS::Util;
use OpenNMS::Release;
use OpenNMS::Release::YumRepo 2.0.0;
use OpenNMS::Release::RPMPackage 2.0.0;

print $0 . ' ' . version->new($OpenNMS::Release::VERSION) . "\n";

my $default_rpm_version  = '1.0';
my $default_rpm_release  = 100;
my $help                 = 0;

my $SIGNING_PASSWORD     = undef;
my $SIGNING_ID           = 'opennms@opennms.org';
my $BRANCH               = 0;
my $REPOFILEDIR          = undef;

my $result = GetOptions(
        "h|help"     => \$help,
        "s|sign=s"   => \$SIGNING_PASSWORD,
        "g|gpg-id=s" => \$SIGNING_ID,
	"b|branch"   => \$BRANCH,
	"d|dir=s"    => \$REPOFILEDIR,
);

my ($base, $release, $platform) = @ARGV;

if ($help) {
	usage();
}

if (not defined $platform) {
	usage('You must specify a base, release, and platform!');
}

if (not defined $SIGNING_PASSWORD or not defined $SIGNING_ID) {
	usage('You must specify a GPG ID and password!');
}

$base = Cwd::abs_path($base);
my $scrubbed_release = $release;
$scrubbed_release =~ s/[^[:alnum:]\.]+/\-/g;
$scrubbed_release =~ s/\-*$//g;

my $rpmname = "opennms-repo-${scrubbed_release}";
if ($BRANCH) {
	$rpmname = "opennms-repo-branches-${scrubbed_release}";
}

my $repofiledir = defined $REPOFILEDIR? Cwd::abs_path($REPOFILEDIR) : File::Spec->catfile($base, 'repofiles');
mkpath($repofiledir);

my $existing_rpm = undef;
opendir(DIR, $repofiledir) or die "Can't read from $repofiledir: $!\n";
while (my $entry = readdir(DIR)) {
	if ($entry =~ /^${rpmname}-/ and $entry =~ /\.rpm$/) {
		my $filename = File::Spec->catfile($repofiledir, $entry);
		$existing_rpm = OpenNMS::Release::RPMPackage->new($filename);
	}
}
closedir(DIR) or die "Can't close directory $repofiledir: $!\n";

my $rpm_version = defined $existing_rpm? ($existing_rpm->version->version)     : $default_rpm_version;
my $rpm_release = defined $existing_rpm? ($existing_rpm->version->release + 1) : $default_rpm_release;

print "- generating YUM repository RPM $rpmname, version $rpm_version-$rpm_release:\n";

my $platform_descriptions = read_properties(dist_file('OpenNMS-Release', 'platform.properties'));
my $gpgfile               = File::Spec->catfile($repofiledir, 'OPENNMS-GPG-KEY');

# first, we make sure OPENNMS-GPG-KEY is up-to-date with the key we're signing with
create_gpg_file($SIGNING_ID, $SIGNING_PASSWORD, $gpgfile);

# then, create the .repo files
create_repo_file($release, $platform, $repofiledir, $platform_descriptions->{$platform}, $scrubbed_release, $rpmname);

# generate an RPM which includes the GPG key and .repo files
my $generated_rpm_filename = create_repo_rpm($release, $platform, $repofiledir, $rpm_version, $rpm_release, $scrubbed_release, $rpmname);

# sign the resultant RPM
sign_rpm($generated_rpm_filename, $SIGNING_ID, $SIGNING_PASSWORD);

# copy it to repofiles/
my $repofiles_rpm_filename = install_rpm_to_repofiles($generated_rpm_filename, $repofiledir, $release, $platform, $scrubbed_release, $rpmname);

# copy *that* to the real repository
#install_rpm_to_repo($repofiles_rpm_filename, $repo, $SIGNING_ID, $SIGNING_PASSWORD);

sub create_gpg_file {
	my $SIGNING_ID       = shift;
	my $SIGNING_PASSWORD = shift;
	my $outputfile       = shift;

	print "- writing GPG key to $outputfile... ";
	gpg_write_key($SIGNING_ID, $SIGNING_PASSWORD, $outputfile);
	print "done.\n";
}

sub create_repo_file {
	my $release          = shift;
	my $platform         = shift;
	my $outputdir        = shift;
	my $description      = shift;
	my $scrubbed_release = shift;
	my $rpmname          = shift;

	print "- creating YUM repository file for ${scrubbed_release}/${platform}... ";

	my $release_description = $release;
	if ($BRANCH) {
		$release_description .= ' branch';
	}

	my $repohandle = IO::Handle->new();
	my $repofilename = File::Spec->catfile($outputdir, "${rpmname}-${platform}.repo");
	open($repohandle, '>' . $repofilename) or die "unable to write to $repofilename: $!";

	my $output = "";
	for my $plat ('common', $platform) {
		my $description = $platform_descriptions->{$plat};
		
		my $baseurl = 'http://yum.mirrors.opennms.org/' . $release . '/' . $plat;
		if ($BRANCH) {
			$baseurl = 'http://yum.mirrors.opennms.org/branches/' . $scrubbed_release . '/' . $plat;
		}

		$output .= <<END;
[${rpmname}-${plat}]
name=${description} (${release_description})
baseurl=${baseurl}
gpgcheck=1
gpgkey=file:///etc/yum.repos.d/${rpmname}-${platform}.gpg

END
	}
	print $repohandle $output;

	close($repohandle);

	print "done.\n";

	return 1;
}

sub create_repo_rpm {
	my $release          = shift;
	my $platform         = shift;
	my $repofiledir      = shift;
	my $rpm_version      = shift;
	my $rpm_release      = shift;
	my $scrubbed_release = shift;
	my $rpmname          = shift;

	print "- creating RPM build structure... ";
	my $dir = tempdir( CLEANUP => 1 );
	for my $subdir ('tmp', 'SPECS', 'SOURCES', 'RPMS', 'SRPMS', 'BUILD') {
		my $path = File::Spec->catfile($dir, $subdir);
		mkpath($path) or die "unable to create path $path: $!";
	}
	for my $subdir ('noarch', 'i386', 'x86_64') {
		my $path = File::Spec->catfile($dir, 'RPMS', $subdir);
		mkpath($path) or die "unable to create path $path: $!";
	}

	my $sourcedir = File::Spec->catfile($dir, 'SOURCES');
	for my $file ("OPENNMS-GPG-KEY", "${rpmname}-${platform}.repo") {
		my $from = File::Spec->catfile($repofiledir, $file);
		my $to   = File::Spec->catfile($sourcedir, $file);
		copy($from, $to) or die "unable to copy $from to $to: $!";
	}
	copy(File::Spec->catfile($sourcedir, 'OPENNMS-GPG-KEY'), File::Spec->catfile($sourcedir, "${rpmname}-${platform}.gpg"));
	print "done.\n";

	print "- creating YUM repository RPM for ${scrubbed_release}/${platform}:\n";

	my $tree = $scrubbed_release;
	if ($BRANCH) {
		$tree = "branches/${scrubbed_release}";
	}

	system(
		'rpmbuild',
		'-bb',
		'--nosignature',
		"--buildroot=${dir}/tmp/buildroot",
		'--define', "_topdir ${dir}",
		'--define', "_tree ${tree}",
		'--define', "_osname ${platform}",
		'--define', "_version ${rpm_version}",
		'--define', "_release ${rpm_release}",
		'--define', '_signature \%{nil}',
		'--define', "_rpmname ${rpmname}",
		'--define', 'vendor The OpenNMS Group, Inc.',
		dist_file('OpenNMS-Release', 'repo.spec')
	) == 0 or die "unable to build rpm: $!";

	print "- finished creating RPM for ${tree}/${platform}.\n";

	return File::Spec->catfile($dir, "RPMS", "noarch", "${rpmname}-${rpm_version}-${rpm_release}.noarch.rpm");
}

sub sign_rpm {
	my $rpm_filename     = shift;
	my $SIGNING_ID       = shift;
	my $SIGNING_PASSWORD = shift;

	print "- signing $rpm_filename... ";
	my $signed = OpenNMS::Release::RPMPackage->new($rpm_filename)->sign($SIGNING_ID, $SIGNING_PASSWORD);
	die "failed while signing RPM: $!" unless ($signed);
	print "- done signing.\n";

	return 1;
}

sub install_rpm_to_repofiles {
	my $source_rpm_filename = shift;
	my $repofiledir         = shift;
	my $release             = shift;
	my $platform            = shift;
	my $scrubbed_release    = shift;
	my $rpmname             = shift;

	my $target_rpm_filename = File::Spec->catfile($repofiledir, "${rpmname}-${platform}.noarch.rpm");
	print "- copying repo rpm to ${target_rpm_filename}... ";
	copy($source_rpm_filename, $target_rpm_filename) or die "Unable to copy $source_rpm_filename to $repofiledir: $!";
	print "done\n";

	return $target_rpm_filename;
}

sub install_rpm_to_repo {
	my $rpm_filename     = shift;
	my $repo             = shift;
	my $SIGNING_ID       = shift;
	my $SIGNING_PASSWORD = shift;

	print "- creating temporary repository from " . $repo->to_string . "... ";
	my $rpm = OpenNMS::Release::RPMPackage->new($rpm_filename);
	my $newrepo = $repo->create_temporary();
	print "done\n";

	print "- installing $rpm_filename to temporary repo... ";
	$newrepo->install_package($rpm, 'opennms');
	print "done\n";

	print "- reindexing temporary repo... ";
	$newrepo->index({signing_id => $SIGNING_ID, signing_password => $SIGNING_PASSWORD});
	print "done\n";

	print "- replacing repository with updated temporary repo... ";
	$newrepo->replace($repo) or die "Unable to replace " . $repo->to_string . " with " . $newrepo->to_string . "!";
	$repo->clear_cache();
	print "done\n";

	return 1;
}

sub usage {
	my $error = shift;

	print <<END;
usage: $0 [-h] [-g <gpg_id>] <-s signing_password> <base> <release> <platform>

	-h            : print this help
	-b <branch>   : signify the 'release' is a branch name
	-s <password> : sign the rpm using this password for the gpg key
	-g <gpg_id>   : sign using this gpg_id (default: opennms\@opennms.org)
	-d <dir>      : the directory to use for reading/writing repo files and RPMs

	base          : the base directory of the YUM repository
	release       : the release tree (e.g., "stable", "unstable", "snapshot", etc.)
	platform      : the repository platform (e.g., "common", "rhel5", etc.)

END

	if (defined $error) {
		print "ERROR: $error\n\n";
	}

	exit 1;
}
