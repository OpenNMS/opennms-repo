$|++;

use File::Path;
use Data::Dumper;

use Test::More;
BEGIN {
	my $dpkg = `which dpkg 2>/dev/null`;
	if ($? == 0) {
		plan tests => 31;
		use_ok('OpenNMS::Release::DebPackage');
		use_ok('OpenNMS::Release::PackageSet');
	} else {
		plan skip_all => '`dpkg` not found, skipping Debian tests.';
	}
};

rmtree("t/testpackages");

my $packageset = OpenNMS::Release::PackageSet->new();
isa_ok($packageset, 'OpenNMS::Release::PackageSet');

is(scalar(@{$packageset->find_all()}), 0);

$packageset->add(OpenNMS::Release::DebPackage->new("t/packages/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb"));
$packageset->add(OpenNMS::Release::DebPackage->new("t/packages/deb/dists/opennms-1.8/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb"));
$packageset->add(OpenNMS::Release::DebPackage->new("t/packages/deb/dists/opennms-1.8/main/binary-all/opennms_1.8.16-1_all.deb"));

is(scalar(@{$packageset->find_all()}), 3);
is(scalar(@{$packageset->find_newest()}), 2);

is(scalar(@{$packageset->find_by_name('iplike-pgsql84')}), 2);
$package = $packageset->find_newest_by_name('iplike-pgsql84');
ok(defined $package);
is($package->[0]->name, 'iplike-pgsql84');
is($package->[0]->version->version, "2.0.2");

is(scalar(@{$packageset->find_by_name('opennms')}), 1);
$package = $packageset->find_newest_by_name('opennms');
ok(defined $package);
is($package->[0]->name, 'opennms');
is($package->[0]->version->version, "1.8.16");

$packageset->set();
is(scalar(@{$packageset->find_all()}), 0);
$packageset->set(OpenNMS::Release::DebPackage->new("t/packages/deb/dists/nightly-1.11/main/binary-all/opennms_1.11.0-0.20111216.14_all.deb"));
is(scalar(@{$packageset->find_all()}), 1);
is($packageset->find_all()->[0]->name, 'opennms');

$package = OpenNMS::Release::DebPackage->new("t/packages/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb");
$packageset->set(OpenNMS::Release::DebPackage->new("t/packages/deb/dists/opennms-1.8/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb"));
ok($packageset->is_obsolete($package));

$packageset->add($package);
$packagelist = $packageset->find_obsolete();

is(scalar(@{$packagelist}), 1);
is($packagelist->[0]->version->version, '1.0.8');

$packageset->set();
$packageset->add(OpenNMS::Release::DebPackage->new('t/packages/deb/dists/nightly-1.11/main/binary-amd64/iplike-pgsql84_1.0.8-1_amd64.deb'));
$packageset->add(OpenNMS::Release::DebPackage->new('t/packages/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb'));
$packageset->add(OpenNMS::Release::DebPackage->new('t/packages/deb/dists/opennms-1.8/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb'));

is(scalar(@{$packageset->find_all()}), 3);
is(scalar(@{$packageset->find_newest()}), 2);

$packagelist = $packageset->find_newest();
is($packagelist->[0]->arch, 'amd64');
is($packagelist->[0]->version->version, '1.0.8');
is($packagelist->[1]->arch, 'i386');
is($packagelist->[1]->version->version, '2.0.2');

my $iplike_1_i386  = OpenNMS::Release::DebPackage->new('t/packages/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb');
my $iplike_1_amd64 = OpenNMS::Release::DebPackage->new('t/packages/deb/dists/nightly-1.11/main/binary-amd64/iplike-pgsql84_1.0.8-1_amd64.deb');
my $iplike_2_i386  = OpenNMS::Release::DebPackage->new('t/packages/deb/dists/opennms-1.8/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb');

$packageset->set();
$packageset->add($iplike_1_i386);
$packageset->remove($iplike_1_i386);

is(scalar(@{$packageset->find_all()}), 0);

$packageset->set();
$packageset->add($iplike_1_i386);
$packageset->add($iplike_1_amd64);
$packageset->remove($iplike_1_i386);

is(scalar(@{$packageset->find_all()}), 1);

$packageset->set();
$packageset->add($iplike_1_i386);
$packageset->add($iplike_2_i386);
$packageset->remove($iplike_1_i386);

is(scalar(@{$packageset->find_all()}), 1);

$packageset->set();
$packageset->add($iplike_1_i386);
$packageset->add($iplike_1_amd64);
$packageset->add($iplike_2_i386);
$packageset->remove($iplike_2_i386);

is(scalar(@{$packageset->find_all()}), 2);

$packageset->set();
$packageset->add($iplike_1_i386);
$packageset->add($iplike_2_i386);
$packageset->remove($iplike_2_i386);

is(scalar(@{$packageset->find_all()}), 1);

rmtree("t/testpackages");
