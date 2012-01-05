# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl OpenNMS-YUM.t'

$|++;

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use File::Path;
use Data::Dumper;
use OpenNMS::YUM::RPM;
#use Test::More tests => 3;
use Test::More skip_all => "This was just for prototyping our real script.";

BEGIN {
	use_ok('OpenNMS::YUM::Repo');
};
import OpenNMS::YUM::Repo::RPMSet;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

our @ORDER = qw(obsolete stable testing unstable snapshot bleeding);
#our $temprepo = "t/realrepo";
our $temprepo = "/opt/temprepo";

#rmtree($temprepo);

my $repos = OpenNMS::YUM::Repo->find_repos("/opt/yum");
is(scalar(@$repos), 114);

my @testrepos;
for my $repo (@$repos) {
#	next unless ($repo->platform eq "common" or $repo->platform eq "rhel5");
#	next unless (grep { $_ eq $repo->release } @ORDER);
	#push(@testrepos, $repo->copy($temprepo));
	push(@testrepos, OpenNMS::YUM::Repo->new($temprepo, $repo->release, $repo->platform));
}
is(scalar(@testrepos), 114);

my $repo_map = {};

for my $repo (@testrepos) {
	my $path = $repo->path;
	`find '$path' -type l -exec rm -rf {} \\;`;
	$repo->clear_cache();

	$repo_map->{$repo->base}->{$repo->release}->{$repo->platform} = $repo;
}

sub not_opennms {
	# return 1;
	return $_[0]->name !~ /^opennms/;
}

for my $i (0 .. ($#ORDER - 1)) {
	my $release = $ORDER[$i];
	my $next_release = $ORDER[$i + 1];
	for my $repo (@testrepos) {
		next unless ($repo->release eq $release);
		if ($repo->release eq $ORDER[0]) {
			print STDERR "\ndeleting obsolete RPMs in " . $repo->to_string . "... ";
			print STDERR $repo->delete_obsolete_rpms(\&not_opennms);
		}

		my $next_repo = $repo_map->{$repo->base}->{$next_release}->{$repo->platform};

		print STDERR "\nsharing all rpms from " . $repo->to_string . " to " . $next_repo->to_string . "... ";
		print STDERR $next_repo->share_all_rpms($repo);

		print STDERR "\ndeleting obsolete RPMs in " . $next_repo->to_string . "... ";
		print STDERR $next_repo->delete_obsolete_rpms(\&not_opennms);
	}
}

print STDERR "\n";

for my $repo (@testrepos) {
	print STDERR "\nindexing " . $repo->to_string . "... ";
	print STDERR $repo->index_if_necessary ? "ok" : "skipped";
}

my $stats = OpenNMS::YUM::RPM->stats();
for my $key (sort keys %$stats) {
	print STDERR "\n$key: " . $stats->{$key};
}
print STDERR "\n\n";

#rmtree($temprepo);
