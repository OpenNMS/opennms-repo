$|++;

use Cwd;
use File::Path;
use Data::Dumper;
use Test::More;
BEGIN {
	my $package = `which rpm 2>/dev/null`;
	if ($? == 0) {
		plan tests => 40;
		use_ok('OpenNMS::Release::RPMPackage');
		use_ok('OpenNMS::Release::YumRepo');
	} else {
		plan skip_all => '`rpm` not found, skipping RPM tests.';
	}
};

my $t = Cwd::abs_path("t");

rmtree("$t/testpackages/rpm");

my $stable_ro = OpenNMS::Release::YumRepo->new("$t/packages/rpm", "stable", "common");
isa_ok($stable_ro, 'OpenNMS::Release::YumRepo');

is($stable_ro->base, "$t/packages/rpm");
is($stable_ro->release, "stable");
is($stable_ro->platform, "common");

my $stable_copy = $stable_ro->copy("$t/testpackages/rpm");
ok(-d "$t/testpackages/rpm");
ok(-d "$t/testpackages/rpm/stable/common");
ok(-f "$t/testpackages/rpm/stable/common/opennms/opennms-1.8.16-1.noarch.rpm");

$stable_copy->delete();
ok(! -d "$t/testpackages/rpm/stable/common");

my ($stable_common, $stable_rhel5, $bleeding_common, $bleeding_rhel5);

reset_repos();

my $packagelist = $stable_common->find_all_packages();
is(scalar(@{$packagelist}), 1);

my $package = $packagelist->[0];
isa_ok($package, 'OpenNMS::Release::RPMPackage');
is($package->name, 'opennms');

$packagelist = $bleeding_common->find_all_packages();
is(scalar(@{$packagelist}), 1);

$bleeding_common->install_package($package, "opennms");
ok(-f "$t/testpackages/rpm/bleeding/common/opennms/opennms-1.8.16-1.noarch.rpm");

$packagelist = $bleeding_common->find_all_packages();
is(scalar(@{$packagelist}), 2);

# make sure that we don't get duplicate entries in the RPM set if we
# install an existing RPM
$bleeding_common->install_package($package, "opennms");
$packagelist = $bleeding_common->find_all_packages();
is(scalar(@{$packagelist}), 2);

($package) = $bleeding_common->find_newest_package_by_name("opennms", "noarch");
is($package->name, "opennms");
is($package->version->version, "1.11.0");

$packagelist = $stable_rhel5->find_all_packages();
is(scalar(@{$packagelist}), 1);

$package = $packagelist->[0];
$bleeding_rhel5->share_package($stable_rhel5, $package);
ok(-f "$t/testpackages/rpm/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm" and not -l "$t/testpackages/rpm/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm");

$packagelist = $bleeding_rhel5->find_newest_packages();
is(scalar(@{$packagelist}), 2);

$packagelist = $bleeding_rhel5->find_all_packages();
is(scalar(@{$packagelist}), 3);

$bleeding_rhel5->share_package($stable_rhel5, $package);
ok(-f "$t/testpackages/rpm/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm" and not -l "$t/testpackages/rpm/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm");

$packagelist = $bleeding_rhel5->find_all_packages();
is(scalar(@{$packagelist}), 3);

$packagelist = $bleeding_rhel5->find_obsolete_packages();

is(scalar(@{$packagelist}), 1);
is($packagelist->[0]->version->version, "1.0.7");

# subroutine says to not delete any
is($bleeding_rhel5->delete_obsolete_packages(sub { return 0 }), 0);
ok(-e "$t/testpackages/rpm/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm");

# delete any obsolete by default
is($bleeding_rhel5->delete_obsolete_packages(), 1);
ok(! -e "$t/testpackages/rpm/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm");

is($bleeding_common->delete_obsolete_packages(sub { $_[0]->name ne "opennms" }), 0);

reset_repos();

$bleeding_rhel5->share_all_packages($stable_rhel5);

$packagelist = $bleeding_rhel5->find_all_packages();
is(scalar(@{$packagelist}), 3);

$packagelist = $bleeding_rhel5->find_newest_packages();
is(scalar(@{$packagelist}), 2);

# this should delete the old iplike-1.0.7-1.i386
is($bleeding_rhel5->delete_obsolete_packages(), 1);
$package = $bleeding_rhel5->find_newest_package_by_name('iplike', 'i386');
is($package->version->version, '2.0.2');
$package = $bleeding_rhel5->find_newest_package_by_name('iplike', 'x86_64');
is($package->version->version, '1.0.7');

my $copy = $bleeding_rhel5->copy("$t/copy");
$package = OpenNMS::Release::RPMPackage->new("$t/packages/rpm/stable/common/opennms/opennms-1.8.16-1.noarch.rpm");
$copy->install_package($package, "opennms");
$bleeding_rhel5 = $copy->replace($bleeding_rhel5);
ok(! -d "$t/copy");
$package = $bleeding_rhel5->find_newest_package_by_name("opennms", "noarch");
ok(defined $package);
is($package->version->version, "1.8.16");

$stable_common->delete;
$stable_rhel5->delete;
$bleeding_common->delete;
$bleeding_rhel5->delete;

sub reset_repos {
	rmtree("$t/testpackages/rpm");
	$stable_common   = OpenNMS::Release::YumRepo->new("$t/packages/rpm", "stable", "common")->copy("$t/testpackages/rpm");
	$stable_rhel5    = OpenNMS::Release::YumRepo->new("$t/packages/rpm", "stable", "rhel5")->copy("$t/testpackages/rpm");
	$bleeding_common = OpenNMS::Release::YumRepo->new("$t/packages/rpm", "bleeding", "common")->copy("$t/testpackages/rpm");
	$bleeding_rhel5  = OpenNMS::Release::YumRepo->new("$t/packages/rpm", "bleeding", "rhel5")->copy("$t/testpackages/rpm");
}

