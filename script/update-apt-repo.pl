#!/usr/bin/perl -w

$|++;

use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Find;
use File::Path;
use Getopt::Long qw(:config gnu_getopt);
use IO::Handle;
use version;

use OpenNMS::Util 2.0.0;
use OpenNMS::Release;
use OpenNMS::Release::Repo 2.7.3;
use OpenNMS::Release::AptRepo 2.7.3;
use OpenNMS::Release::DebPackage 2.1.0;

print $0 . ' ' . version->new($OpenNMS::Release::VERSION) . "\n";

my $HELP             = 0;
my $ALL              = 0;
my $RESIGN           = 0;
my $NO_OBSOLETE      = 0;
my $NO_SYNC          = 0;

my $BRANCH           = undef;
my $SIGNING_PASSWORD = undef;
my $SIGNING_ID       = 'opennms@opennms.org';

my $result = GetOptions(
	"h|help"        => \$HELP,
	"a|all"         => \$ALL,
	"b|branch=s"    => \$BRANCH,
	"n|no-sync"     => \$NO_SYNC,
	"s|sign=s"      => \$SIGNING_PASSWORD,
	"g|gpg-id=s"    => \$SIGNING_ID,
	"r|resign"      => \$RESIGN,
	"o|no-obsolete" => \$NO_OBSOLETE,
);

my ($BASE, $RELEASE, @PACKAGES);

$BASE = shift @ARGV;
if (not defined $BASE) {
	usage("You did not specify an APT repository base!");
}
$BASE = Cwd::abs_path($BASE);

if ($HELP) {
	usage();
}

if (not $ALL) {
	($RELEASE, @PACKAGES) = @ARGV;
	if (not defined $RELEASE) {
		usage("You must specify a repository base and release!");
	}
}

my @all_repositories = @{OpenNMS::Release::AptRepo->find_repos($BASE)};

@all_repositories = sort {
	my ($a_name, $a_version) = $a->release =~ /^(.*?)-([\d\.]+)$/;
	my ($b_name, $b_version) = $b->release =~ /^(.*?)-([\d\.]+)$/;

	die "unable to determine name/revision from " . $a->release unless (defined $a_version);
	die "unable to determine name/revision from " . $b->release unless (defined $b_version);

	if ($a_version eq $b_version) {
		return $a_name eq "opennms"? -1 : 1;
	}
	return (system('dpkg', '--compare-versions', $a_version, '<<', $b_version) == 0)? -1 : 1;
} @all_repositories;

my $scan_repositories = [];
if ($ALL) {
	$scan_repositories = \@all_repositories;
} else {
	my $releasedir = File::Spec->catdir($BASE, 'dists', $RELEASE);
	if (-l $releasedir) {
		$RELEASE = basename(readlink($releasedir));
	}
	$scan_repositories = [ OpenNMS::Release::AptRepo->new($BASE, $RELEASE) ];
}

my @sync_order = map { $_->release } @all_repositories;

if (not $NO_SYNC) {
	for my $orig_repo (@$scan_repositories) {
		print "* syncing ", $orig_repo->to_string, "... ";
		sync_repos($BASE, $orig_repo, $SIGNING_ID, $SIGNING_PASSWORD);
		print "done\n";
	}
}

if (defined $BRANCH) {
	print "* syncing base to $BRANCH branch repo:\n";
	# first, copy from the release branch to the temporary one
	my $from_repo = OpenNMS::Release::AptRepo->new($BASE, $RELEASE);
	my $to_repo   = OpenNMS::Release::AptRepo->new($BASE, 'branches/' . $BRANCH);
	sync_repo($from_repo, $to_repo, $SIGNING_ID, $SIGNING_PASSWORD);

	# then, update with the new Debs
	update_repo($to_repo, $RESIGN, $SIGNING_ID, $SIGNING_PASSWORD, @PACKAGES);

	exit 0;
}

for my $orig_repo (@$scan_repositories) {
	print "* syncing and updating ", $orig_repo->to_string, "... ";
	update_repo($orig_repo, $RESIGN, $SIGNING_ID, $SIGNING_PASSWORD, @PACKAGES);
	sync_repos($BASE, $orig_repo, $SIGNING_ID, $SIGNING_PASSWORD);
	print "done\n";
}

sub update_repo {
	my $from_repo        = shift;
	my $resign           = shift;
	my $signing_id       = shift;
	my $signing_password = shift;
	my @packages         = @_;

	my $base     = $from_repo->abs_base;
	my $release  = $from_repo->release;

	print "=== Updating repo files in: $base/dists/$release/ ===\n";

	my $to_repo = $from_repo->create_temporary;

	if ($resign) {
		$to_repo->sign_all_packages($signing_id, $signing_password, undef, \&display);
	}

	if (@packages) {
		install_packages($to_repo, @packages);
	}

	index_repo($to_repo, $signing_id, $signing_password);

	$to_repo->replace($from_repo) or die "Unable to replace " . $from_repo->to_string . " with " . $to_repo->to_string . "!";
}

if (defined $SIGNING_ID and defined $SIGNING_PASSWORD) {
	gpg_write_key($SIGNING_ID, $SIGNING_PASSWORD, File::Spec->catfile($BASE, 'OPENNMS-GPG-KEY'));
}

sub display {
	my $package = shift;
	my $count   = shift;
	my $total   = shift;
	my $sign    = shift;

	print "- " . $package->to_string . " ($count/$total, " . ($sign? 'resigned':'skipped') . ")\n";
}

# return 1 if the obsolete package given should be deleted
sub not_opennms {
	my ($package, $repo) = @_;
	if ($package->name =~ /opennms/) {
		# we keep all *opennms* packages in official release dirs
		if ($repo->release =~ /^(obsolete|stable|unstable|opennms-[\d\.]+)$/) {
			return 0;
		} else {
			# otherwise, delete old opennms packages
			return 1;
		}
	}

	# keep any other 3rd-party packages
	return 0;
}

sub install_packages {
	my $release_repo = shift;
	my @packages = @_;

	if (@packages) {
		print "* installing " . scalar(@packages) . " packages:\n";
		for my $packagename (@packages) {
			my $package = OpenNMS::Release::DebPackage->new(Cwd::abs_path($packagename));
			my $existing = $release_repo->find_newest_package_by_name($package->name, $package->arch);
			if ($existing && !$NO_OBSOLETE) {
				print "  * removing existing package: " . $existing->to_string . "... ";
				$release_repo->delete_package($existing);
				print "done.\n";
			}
			print "  * installing package: " . $package->to_string . "... ";
			$release_repo->install_package($package);
			print "done.\n";
		}
	}
}

sub index_repo {
	my $release_repo     = shift;
	my $signing_id       = shift;
	my $signing_password = shift;

	if (!$NO_OBSOLETE) {
		print "- removing obsolete packages from repo: " . $release_repo->to_string . "... ";
		my $removed = $release_repo->delete_obsolete_packages(\&not_opennms);
		print $removed . " packages removed.\n";
	}

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

	for my $i ((get_release_index($release_repo->release) + 1) .. $#sync_order) {
		my $rel = $sync_order[$i];

		my $to_repo = OpenNMS::Release::AptRepo->new($base, $rel);
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
	print $num_shared . " packages updated.\n";

	if (!$NO_OBSOLETE) {
		print "- removing obsolete packages from repo: " . $temp_repo->to_string . "... ";
		my $num_removed = $temp_repo->delete_obsolete_packages(\&not_opennms);
		print $num_removed . " packages removed.\n";
	}

	print "- indexing repo: " . $temp_repo->to_string . "... ";
	my $indexed = $temp_repo->index_if_necessary({ signing_id => $signing_id, signing_password => $signing_password });
	print $indexed? "done.\n" : "skipped.\n";

	my $ret = $temp_repo->replace($to_repo, 1) or die "Unable to replace " . $to_repo->to_string . " with " . $temp_repo->to_string . "!";
	return $ret;
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
usage: $0 [-h] [-s <password>] [-g <signing_id>] ( -a <base> | [-b <branch_name>] <base> <release> [package...] )

	-h            : print this help
	-a            : update all repositories (release and packages will be ignored in this case)
	-r            : re-sign packages in the repositor(y|ies)
	-s <password> : sign the package using this password for the gpg key
	-g <gpg_id>   : sign using this gpg_id (default: opennms\@opennms.org)
	-n            : don't sync up all repositories
	-o            : don't remove obsolete packages

	base          : the base directory of the APT repository
	release       : the release tree (e.g., "opennms-1.8", "nightly-1.9", etc.)
	package...    : 0 or more packages to add to the repository

END

	if (defined $error) {
		print "ERROR: $error\n\n";
	}

	exit 1;
}

