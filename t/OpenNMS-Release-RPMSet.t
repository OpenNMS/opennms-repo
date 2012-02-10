$|++;

use strict;
use warnings;

use Cwd;
use File::Path;
use Data::Dumper;

use Test::More;
BEGIN {
	my $package = `which rpm 2>/dev/null`;
	if ($? == 0) {
		plan tests => 26;
		use_ok('OpenNMS::Release::RPMPackage');
		use_ok('OpenNMS::Release::PackageSet');
	} else {
		plan skip_all => '`rpm` not found, skipping RPM tests.';
	}
};

my ($t, $package, $packagelist, $packageset);

$t = Cwd::abs_path('t');

$packageset = OpenNMS::Release::PackageSet->new();
isa_ok($packageset, 'OpenNMS::Release::PackageSet');

is(scalar(@{$packageset->find_all()}), 0);

$packageset->add(OpenNMS::Release::RPMPackage->new("$t/packages/rpm/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm"));
$packageset->add(OpenNMS::Release::RPMPackage->new("$t/packages/rpm/stable/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm"));
$packageset->add(OpenNMS::Release::RPMPackage->new("$t/packages/rpm/stable/common/opennms/opennms-1.8.16-1.noarch.rpm"));

is(scalar(@{$packageset->find_all()}), 3);
is(scalar(@{$packageset->find_newest()}), 2);

is(scalar(@{$packageset->find_by_name("iplike")}), 2);
$package = $packageset->find_newest_by_name("iplike");
ok(defined $package);
is($package->[0]->name, "iplike");
is($package->[0]->version->version, "2.0.2");

is(scalar(@{$packageset->find_by_name("opennms")}), 1);
$package = $packageset->find_newest_by_name("opennms");
ok(defined $package);
is($package->[0]->name, "opennms");
is($package->[0]->version->version, "1.8.16");

$packageset->set();
is(scalar(@{$packageset->find_all()}), 0);
$packageset->set(OpenNMS::Release::RPMPackage->new("$t/packages/rpm/bleeding/common/opennms/opennms-1.11.0-0.20111220.1.noarch.rpm"));
is(scalar(@{$packageset->find_all()}), 1);
is($packageset->find_all()->[0]->name, "opennms");

$package = OpenNMS::Release::RPMPackage->new("$t/packages/rpm/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm");
$packageset->set(OpenNMS::Release::RPMPackage->new("$t/packages/rpm/stable/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm"));
ok($packageset->is_obsolete($package));

$packageset->add($package);
$packagelist = $packageset->find_obsolete();

is(scalar(@{$packagelist}), 1);
is($packagelist->[0]->version->version, "1.0.7");

$packageset->set();
$packageset->add(OpenNMS::Release::RPMPackage->new("$t/packages/rpm/bleeding/rhel5/opennms/x86_64/iplike-1.0.7-1.x86_64.rpm"));
$packageset->add(OpenNMS::Release::RPMPackage->new("$t/packages/rpm/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm"));
$packageset->add(OpenNMS::Release::RPMPackage->new("$t/packages/rpm/stable/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm"));

is(scalar(@{$packageset->find_all()}), 3);
is(scalar(@{$packageset->find_newest()}), 2);

$packagelist = $packageset->find_newest();
is($packagelist->[0]->arch, 'i386');
is($packagelist->[0]->version->version, '2.0.2');
is($packagelist->[1]->arch, 'x86_64');
is($packagelist->[1]->version->version, '1.0.7');
