#!/usr/bin/perl -w

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
use OpenNMS::Release::YumRepo 2.10.0;
use OpenNMS::Release::RPMPackage 2.0.0;

print $0 . ' ' . version->new($OpenNMS::Release::VERSION) . "\n";

my $HELP             = 0;
my $ALL              = 0;
my $RESIGN           = 0;
my $REINDEX          = 0;
my $NO_SYNC          = 0;
my $NO_DELTAS        = 0;
my $NO_OBSOLETE      = 0;

my $BRANCH           = undef;
my $CACHEDIR         = undef;
my $SIGNING_PASSWORD = undef;
my $SIGNING_ID       = 'opennms@opennms.org';

my $result = GetOptions(
	"h|help"        => \$HELP,
	"a|all"         => \$ALL,
	"b|branch=s"    => \$BRANCH,
	"c|cache-dir=s" => \$CACHEDIR,
	"d|no-deltas"   => \$NO_DELTAS,
	"g|gpg-id=s"    => \$SIGNING_ID,
	"i|reindex"     => \$REINDEX,
	"n|no-sync"     => \$NO_SYNC,
	"o|no-obsolete" => \$NO_OBSOLETE,
	"r|resign"      => \$RESIGN,
	"s|sign=s"      => \$SIGNING_PASSWORD,
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

if ($CACHEDIR) {
	$OpenNMS::Release::YumRepo::CREATEREPO_USE_GLOBAL_CACHE = $CACHEDIR;
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
		$SUBDIRECTORY = 'opennms';
	}
}

my $releases = {};

my $release_descriptions = read_properties(dist_file('OpenNMS-Release', 'release.properties'));
my @sync_order = split(/\s*,\s*/, $release_descriptions->{order_sync});
delete $release_descriptions->{order_sync};

my $platforms = read_properties(dist_file('OpenNMS-Release', 'platform.properties'));
my @platform_order = split(/\s*,\s*/, $platforms->{order_display});
delete $platforms->{order_display};

my @core_rpms = grep { /\bmeridian-core-/ } @RPMS;
if (exists $core_rpms[0]) {
	my $core_rpm = OpenNMS::Release::RPMPackage->new(Cwd::abs_path($core_rpms[0]));
	my $version = $core_rpm->version->version();
	($version) = $version =~ /^(\d+)\./;
	if ($version >= 2017) {
		print "! Meridian 2017 or newer package found. Skipping rhel5 sync.\n";
		@platform_order = grep { !/(centos5|rhel5)/i } @platform_order;
	}
	if ($version >= 2019) {
		print "! Meridian 2019 or newer package found. Skipping rhel6 sync.\n";
		@platform_order = grep { !/(centos6|rhel6)/i } @platform_order;
	}
}

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
#for my $release (@sync_order) {
#	next unless (exists $releases->{$release});
#
#	for my $platform ("common", sort keys %{$releases->{$release}}) {
#		my $repo = $releases->{$release}->{$platform};
#		sync_repos($BASE, $repo, $SIGNING_ID, $SIGNING_PASSWORD);
#	}
#}

# then if this branch needs updating, do it
if (defined $BRANCH) {
	my $branch_base = File::Spec->catdir($BASE, 'branches');

	# ensure that the platform currently being indexed gets updated
	# otherwise, only update distro-specific platforms and not "common"
	my @platforms = grep { $_ ne "common" } @platform_order;
	if (not grep { /^${PLATFORM}$/ } @platforms) {
		unshift(@platforms, $PLATFORM);
	}

	# first, make sure we have all the platform repos for the branch
	for my $platform (@platforms) {
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
#if ($NO_SYNC) {
#	my $repo = $releases->{$RELEASE}->{$PLATFORM};
#	update_platform($repo, $RESIGN, $SIGNING_ID, $SIGNING_PASSWORD, $SUBDIRECTORY, @RPMS);
#} else {
	for my $release (keys %$releases) {
		next unless (exists $releases->{$release});

		for my $platform (sort keys %{$releases->{$release}}) {
			my $repo = $releases->{$release}->{$platform};
			update_platform($repo, $RESIGN, $SIGNING_ID, $SIGNING_PASSWORD, $SUBDIRECTORY, @RPMS);
			sync_repos($BASE, $repo, $SIGNING_ID, $SIGNING_PASSWORD);
		}
	}
#}

sub update_platform {
	my $orig_repo        = shift;
	my $resign           = shift;
	my $signing_id       = shift;
	my $signing_password = shift;
	my $subdirectory     = shift;
	my @rpms             = @_;

	my $dirty    = 0;
	my $base     = $orig_repo->abs_base;
	my $release  = $orig_repo->release;
	my $platform = $orig_repo->platform;

	print "=== Updating repo files in: $base/$release/$platform/ ===\n";

	if ($resign or @rpms) {
		$dirty++;
	}

	if ($REINDEX) {
		print "- forcing reindex of $base/$release/$platform/:\n";
		$dirty++;
	}

#	if (not $dirty) {
#		my $obsolete = $orig_repo->find_obsolete_packages();
#		if (@$obsolete) {
#			$dirty++;
#		}
#	}

	if ($dirty) {
		print "- creating temporary repository from " . $orig_repo->to_string . "... ";
		my $release_repo = $orig_repo->create_temporary;
		print "done.\n";

		if ($resign) {
			print "- re-signing packages in " . $release_repo->to_string . "... ";
			$release_repo->sign_all_packages($signing_id, $signing_password, undef, \&display);
			print "done.\n";
		}

		if (defined $subdirectory and @rpms) {
			install_rpms($release_repo, $subdirectory, @rpms);
		}

		index_repo($release_repo, $signing_id, $signing_password);

		print "- replacing " . $orig_repo->to_string . " with " . $release_repo->to_string . "... ";
		$release_repo = $release_repo->replace($orig_repo) or die "Unable to replace " . $orig_repo->to_string . " with " . $release_repo->to_string . "!";
		print "done.\n";
	} else {
		print "- No updates made.  Skipping.\n";
	}
}

# return 1 if the obsolete RPM given should be deleted
sub only_snapshot {
	my ($rpm, $repo) = @_;
	if ($rpm->name =~ /^(opennms|meridian)/) {
		# we remove old snapshot RPMs
		if ($rpm->version->release =~ /^0\./) {
			return 1;
		}
	}

	return 0;
}

sub install_rpms {
	my $release_repo = shift;
	my $subdirectory = shift;
	my @rpms = @_;

	if (@rpms) {
		print "- installing " . scalar(@rpms) . " packages:\n";
		for my $rpmname (@rpms) {
			my $rpm = OpenNMS::Release::RPMPackage->new(Cwd::abs_path($rpmname));
			my $existing = $release_repo->find_newest_package_by_name($rpm->name, $rpm->arch);
			if ($existing) {
				print "  - removing existing package: " . $existing->to_string . "... ";
				$release_repo->delete_package($existing);
				print "done.\n";
			}
			print "  * installing package: " . $rpm->to_string . "... ";
			$release_repo->install_package($rpm, $subdirectory);
			print "done.\n";
		}
	}
}

sub index_repo {
	my $release_repo     = shift;
	my $signing_id       = shift;
	my $signing_password = shift;

	if (!$NO_OBSOLETE) {
		print "- removing obsolete RPMs from repo: " . $release_repo->to_string . "... ";
		my $removed = $release_repo->delete_obsolete_packages(\&only_snapshot);
		print $removed . " RPMs removed.\n";
	}

	print "- reindexing repo: " . $release_repo->to_string . "... ";
	$release_repo->enable_deltas(0) if ($NO_DELTAS);
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

	my $from_packages = $from_repo->packageset();
	my $to_packages   = $to_repo->packageset();
	if (not $from_packages or not $to_packages or $from_packages->has_newer_than($to_packages)) {
		print "- sync_repo " . $from_repo->to_string . " -> " . $to_repo->to_string . "\n";
	} else {
		print "- no packages in " . $from_repo->to_string . " were newer than " . $to_repo->to_string . "... skipping sync.\n";
		return $to_repo;
	}

	print "- creating temporary repository from " . $to_repo->to_string . "... ";
	my $temp_repo = $to_repo->create_temporary;
	print "done.\n";

#	print "- sharing from repo: " . $from_repo->to_string . " to " . $temp_repo->to_string . "... ";
#	my $num_shared = $temp_repo->share_all_packages($from_repo);
#	print $num_shared . " RPMS updated.\n";
#
#	if (!$NO_OBSOLETE) {
#		print "- removing obsolete RPMs from repo: " . $temp_repo->to_string . "... ";
#		my $num_removed = $temp_repo->delete_obsolete_packages(\&only_snapshot);
#		print $num_removed . " RPMs removed.\n";
#	}

	print "- indexing repo: " . $temp_repo->to_string . "... ";
	$temp_repo->enable_deltas(0) if ($NO_DELTAS);
	my $indexed = $temp_repo->index_if_necessary({ signing_id => $signing_id, signing_password => $signing_password });
	print $indexed? "done.\n" : "skipped.\n";

	print "- replacing " . $to_repo->to_string . " with " . $temp_repo->to_string . "... ";
	my $replaced = $temp_repo->replace($to_repo, 1) or die "Unable to replace " . $to_repo->to_string . " with " . $temp_repo->to_string . "!";
	print $replaced? "done.\n" : "failed.\n";

	return $replaced;
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
	-r            : force re-signing of the packages in the repositor(y|ies)
	-i            : force re-index of the repositor(y|ies)
	-n            : no syncing of extra (platform) repositories
	-s <password> : sign the rpm using this password for the gpg key
	-g <gpg_id>   : sign using this gpg_id (default: opennms\@opennms.org)
	-o            : don't remove obsolete packages

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

