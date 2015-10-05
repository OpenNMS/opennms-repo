#!/usr/bin/perl -w

$|++;

use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Find;
use File::Path;
use File::ShareDir qw(:ALL);
use Getopt::Long qw(:config gnu_getopt);
use IO::Handle;

use OpenNMS::Util 2.0.0;
use OpenNMS::Release;
use OpenNMS::Release::Repo 2.7.2;
use OpenNMS::Release::YumRepo 2.7.2;
use OpenNMS::Release::RPMPackage 2.0.0;

print $0 . ' ' . version->new($OpenNMS::Release::VERSION) . "\n";

my $HELP             = 0;
my $ALL              = 0;
my $RESIGN           = 0;

my $BRANCH           = undef;
my $SIGNING_PASSWORD = undef;
my $SIGNING_ID       = 'opennms@opennms.org';

my $result = GetOptions(
	"h|help"     => \$HELP,
	"a|all"      => \$ALL,
	"b|branch=s" => \$BRANCH,
	"s|sign=s"   => \$SIGNING_PASSWORD,
	"g|gpg-id=s" => \$SIGNING_ID,
	"r|resign"   => \$RESIGN,
);

my ($BASE, $RELEASE, $PLATFORM, $SUBDIRECTORY, @RPMS);

$BASE = shift @ARGV;
if (not defined $BASE) {
	usage("You did not specify a YUM repository base!");
}
$BASE = Cwd::abs_path($BASE);

if ($HELP) {
	usage();
}

if ($RESIGN and not defined $SIGNING_PASSWORD) {
	usage("You specified --resign, but did not provide a password!");
}

if (not $ALL) {
	($RELEASE, $PLATFORM, $SUBDIRECTORY, @RPMS) = @ARGV;
	if (not defined $RELEASE or not defined $PLATFORM) {
		usage("You must specify a YUM repository base, release, and platform!");
	}
	
	if (not defined $SUBDIRECTORY) {
		usage("You must specify a subdirectory.");
	}
}

my $releases = {};

my $release_descriptions = read_properties(dist_file('OpenNMS-Release', 'release.properties'));
my @sync_order = split(/\s*,\s*/, $release_descriptions->{order_sync});
delete $release_descriptions->{order_sync};

my $platforms = read_properties(dist_file('OpenNMS-Release', 'platform.properties'));
my @platform_order = split(/\s*,\s*/, $platforms->{order_display});
delete $platforms->{order_display};

if ($ALL) {
	for my $repo (@{OpenNMS::Release::YumRepo->find_repos($BASE)}) {
		if (not grep { $_ eq $repo->release } @sync_order) {
			warn "Unknown release: " . $repo->release . ", skipping.";
			# push(@sync_order, $repo->release);
		}
		$releases->{$repo->release}->{$repo->platform} = $repo;
	}
} else {
	$releases->{$RELEASE}->{$PLATFORM} = OpenNMS::Release::YumRepo->new($BASE, $RELEASE, $PLATFORM);
}

sub display {
	my $package = shift;
	my $count   = shift;
	my $total   = shift;
	my $sign    = shift;

	print "- " . $package->to_string . " ($count/$total, " . ($sign? 'resigned':'skipped') . ")\n";
}

# merge releases forward first
for my $release (@sync_order) {
	next unless (exists $releases->{$release});

	for my $platform ("common", sort keys %{$releases->{$release}}) {
		my $repo = $releases->{$release}->{$platform};
		sync_repos($BASE, $repo, $SIGNING_ID, $SIGNING_PASSWORD);
	}
}

# then if this branch needs updating, do it
if (defined $BRANCH) {
	my $branch_base = File::Spec->catdir($BASE, 'branches');

	# first, make sure we have all the platform repos for the branch
	for my $platform ("common", @platform_order) {
		my $from_repo = OpenNMS::Release::YumRepo->new($BASE, $RELEASE, $platform);
		my $to_repo   = OpenNMS::Release::YumRepo->new($branch_base, $BRANCH,  $platform);
		sync_repo($from_repo, $to_repo, $SIGNING_ID, $SIGNING_PASSWORD);
	}

	# then, update with the new RPMs
	my $repo = OpenNMS::Release::YumRepo->new($branch_base, $BRANCH, $PLATFORM);
	update_platform($repo, $RESIGN, $SIGNING_ID, $SIGNING_PASSWORD, $SUBDIRECTORY, @RPMS);

	exit 0;
}

# finally, update any platforms that need it
for my $release (@sync_order) {
	next unless (exists $releases->{$release});

	for my $platform (sort keys %{$releases->{$release}}) {
		my $repo = $releases->{$release}->{$platform};
		update_platform($repo, $RESIGN, $SIGNING_ID, $SIGNING_PASSWORD, $SUBDIRECTORY, @RPMS);
		sync_repos($BASE, $repo, $SIGNING_ID, $SIGNING_PASSWORD);
	}
}

sub update_platform {
	my $orig_repo        = shift;
	my $resign           = shift;
	my $signing_id       = shift;
	my $signing_password = shift;
	my $subdirectory     = shift;
	my @rpms             = @_;

	my $base     = $orig_repo->abs_base;
	my $release  = $orig_repo->release;
	my $platform = $orig_repo->platform;

	print "=== Updating repo files in: $base/$release/$platform/ ===\n";

	my $release_repo = $orig_repo->create_temporary;

	if ($resign) {
		$release_repo->sign_all_packages($signing_id, $signing_password, undef, \&display);
	}

	if (defined $subdirectory and @rpms) {
		install_rpms($release_repo, $subdirectory, @rpms);
	}

	index_repo($release_repo, $signing_id, $signing_password);
	
	$release_repo = $release_repo->replace($orig_repo) or die "Unable to replace " . $orig_repo->to_string . " with " . $release_repo->to_string . "!";
}

# return 1 if the obsolete RPM given should be deleted
sub not_opennms {
	my ($rpm, $repo) = @_;
	if ($rpm->name =~ /^opennms/) {
		# we keep all opennms-* RPMs in official release dirs
		if ($repo->release =~ /^(obsolete|stable|unstable)$/) {
			return 0;
		}
	}
	
	return 1;
}

sub install_rpms {
	my $release_repo = shift;
	my $subdirectory = shift;
	my @rpms = @_;

	for my $rpmname (@rpms) {
		my $rpm = OpenNMS::Release::RPMPackage->new(Cwd::abs_path($rpmname));
		$release_repo->install_package($rpm, $subdirectory);
	}
}

sub index_repo {
	my $release_repo     = shift;
	my $signing_id       = shift;
	my $signing_password = shift;

	print "- removing obsolete RPMs from repo: " . $release_repo->to_string . "... ";
	my $removed = $release_repo->delete_obsolete_packages(\&not_opennms);
	print $removed . " RPMs removed.\n";

	print "- reindexing repo: " . $release_repo->to_string . "... ";
	$release_repo->index({ signing_id => $signing_id, signing_password => $signing_password });
	print "done.\n";
}

sub sync_repos {
	my $base             = shift;
	my $release_repo     = shift;
	my $signing_id       = shift;
	my $signing_password = shift;

	my $last_repo = $release_repo;
	if (not defined $release_repo) {
		print "! WARNING: release repo not defined!\n";
		return;
	}

	for my $i ((get_release_index($release_repo->release) + 1) .. $#sync_order) {
		my $rel = $sync_order[$i];

		my $to_repo = OpenNMS::Release::YumRepo->new($base, $rel, $release_repo->platform);
		$last_repo = sync_repo($last_repo, $to_repo, $signing_id, $signing_password);
	}
}

sub sync_repo {
	my $from_repo        = shift;
	my $to_repo          = shift;
	my $signing_id       = shift;
	my $signing_password = shift;

	my $temp_repo = $to_repo->create_temporary;

	print "- sharing from repo: " . $from_repo->to_string . " to " . $temp_repo->to_string . "... ";
	my $num_shared = $temp_repo->share_all_packages($from_repo);
	print $num_shared . " RPMS updated.\n";

	print "- removing obsolete RPMs from repo: " . $temp_repo->to_string . "... ";
	my $num_removed = $temp_repo->delete_obsolete_packages(\&not_opennms);
	print $num_removed . " RPMs removed.\n";

	print "- indexing repo: " . $temp_repo->to_string . "... ";
	my $indexed = $temp_repo->index_if_necessary({ signing_id => $signing_id, signing_password => $signing_password });
	print $indexed? "done.\n" : "skipped.\n";

	return $temp_repo->replace($to_repo, 1) or die "Unable to replace " . $to_repo->to_string . " with " . $temp_repo->to_string . "!";
}

sub get_release_index {
	my $release_name = shift;
	my $index = 0;
	++$index until (($index > $#sync_order) or ($sync_order[$index] eq $release_name));
	return $index;
}

sub usage {
	my $error = shift;

	print <<END;
usage: $0 [-h] [-s <password>] [-g <signing_id>] ( -a <base> | [-b <branch_name>] <base> <release> <platform> <subdirectory> [rpm...] )

	-h            : print this help
	-a            : update all repositories (release, platform, subdirectory, and rpms will be ignored in this case)
	-r            : re-sign packages in the repositor(y|ies)
	-s <password> : sign the rpm using this password for the gpg key
	-g <gpg_id>   : sign using this gpg_id (default: opennms\@opennms.org)

	base          : the base directory of the YUM repository
	release       : the release tree (e.g., "stable", "unstable", "snapshot", etc.)
	platform      : the repository platform (e.g., "common", "rhel5", etc.)
	subdirectory  : the subdirectory with in the base/release/platform repo to place RPMs
	rpm...        : 0 or more RPMs to add to the repository

END

	if (defined $error) {
		print "ERROR: $error\n\n";
	}

	exit 1;
}

