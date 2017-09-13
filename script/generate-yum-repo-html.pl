#!/usr/bin/perl -w

$|++;

use strict;
use warnings;

use Data::Dumper;
use Fcntl qw(LOCK_EX LOCK_NB);
use File::Basename;
use File::NFSLock qw(uncache);
use File::ShareDir qw(:ALL);
use File::Slurp;
use File::Spec;
use version;

use OpenNMS::Util 2.0.0;
use OpenNMS::Release;
use OpenNMS::Release::YumRepo 2.0.0;

print $0 . ' ' . version->new($OpenNMS::Release::VERSION) . "\n";

my $base = shift @ARGV;
my $PASSWORD = undef;

if (not defined $base or not -d $base) {
	print "usage: $0 <repository_base>\n\n";
	exit 1;
}

my $index_text = slurp(dist_file('OpenNMS-Release', 'generate-yum-repo-html.pre'));

my $release_descriptions  = read_properties(dist_file('OpenNMS-Release', 'release.properties'));
my $platform_descriptions = read_properties(dist_file('OpenNMS-Release', 'platform.properties'));

my @display_order  = split(/\s*,\s*/, $release_descriptions->{order_display});
my @platform_order = split(/\s*,\s*/, $platform_descriptions->{order_display});

my $lockfile = File::Spec->catfile($base, '.generate-yum-repo-html.lock');

print "* waiting for lock...\n";
### set up a lock - lasts until object loses scope
if (my $lock = new File::NFSLock {
        file      => $lockfile,
        lock_type => LOCK_EX,
	blocking_timeout   => 30 * 60, # 30 minutes
	stale_lock_timeout => 60 * 60, # 1 hour
}) {
        # update the lock file
        open(FILE, ">$lockfile") || die "Failed to lock $base: $!\n";
        print FILE localtime(time);
        $lock->uncache;
	print "* got lock -- generating yum repo HTML.\n";

##### START UPDATING, INSIDE LOCK #####

my $repos = OpenNMS::Release::YumRepo->find_repos($base);

# convenience hash for looking up repositories
my $repo_map = {};
for my $repo (@$repos) {
	next if ($repo->base =~ m,/branches/,);
	$repo_map->{$repo->release}->{$repo->platform} = $repo;
}

my $passfile = File::Spec->catfile($ENV{'HOME'}, '.signingpass');
if (-e $passfile) {
	chomp($PASSWORD = read_file($passfile));
} else {
	print STDERR "WARNING: $passfile does not exist!  We will be unable to create new repository RPMs.";
}

for my $release (@display_order) {
	next unless (exists $repo_map->{$release});

	my $release_description = $release_descriptions->{$release};

	my $repos  = $repo_map->{$release};
	my $common = $repos->{'common'};

	my $latest_rpm           = $common->find_newest_package_by_name('opennms-core', 'noarch');
	next unless ($latest_rpm);

	my $description          = $latest_rpm->description();
	my ($git_url, $git_hash) = $description =~ /(https:\/\/github\.com\/OpenNMS\/opennms\/commit\/(\S+))$/gs;

	$index_text .= "<h3><a name=\"$release\" href=\"$release/common/opennms\">$release_description</a>: ";
	$index_text .= "<a href=\"$release/common/opennms\">" . $latest_rpm->version->display_version . "</a>";
	if (defined $git_url and defined $git_hash) {
		$index_text .= " <span style=\"float: right\">Git Commit: <a href=\"$git_url\">" . $git_hash . "</a></span>";
	}
	$index_text .= "</h3>\n";

	$index_text .= "<ul>\n";

	$index_text .= "<li>$platform_descriptions->{'common'} (<a href=\"$release/common\">browse</a>)</li>\n";

	for my $platform (@platform_order) {

		my $rpmname = "opennms-repo-$release-$platform.noarch.rpm";

		if ($platform ne "common" and not -e "$base/repofiles/$rpmname") {
			print STDERR "WARNING: repo RPM does not exist for $release/$platform... creating.\n";
			system("create-repo-rpm.pl", "-s", $PASSWORD, $base, $release, $platform) == 0 or die "Failed to create repo RPM: $!\n";
		}

		if (-e "$base/repofiles/$rpmname") {
			$index_text .= "<li><a href=\"repofiles/$rpmname\">$platform_descriptions->{$platform}</a> (<a href=\"$release/$platform\">browse</a>)</li>\n";
		} else {
			if (defined $platform and exists $platform_descriptions->{$platform}) {
				$index_text .= "<li>$platform_descriptions->{$platform} (<a href=\"$release/$platform\">browse</a>)</li>\n";
			} else {
				print STDERR "WARNING: unknown release/platform $release / $platform.\n";
			}
		}

	}

	$index_text .= "</ul>\n";
}

$index_text .= "<p>Index generated: " . localtime(time) . "</p>";
$index_text .= slurp(dist_file('OpenNMS-Release', 'generate-yum-repo-html.post'));

open (FILEOUT, ">$base/index.html") or die "unable to write to $base/index.html: $!";
print FILEOUT $index_text;
close (FILEOUT);

##### FINISHED UPDATING, FINISH LOCK #####

	unlink($lockfile) or die "Failed to remove $lockfile: $!\n";
	close(FILE) or die "Failed to close $lockfile: $!\n";
	$lock->unlock();

	exit 0;
} else {
	die "Couldn't lock $lockfile [$File::NFSLock::errstr]";
}
