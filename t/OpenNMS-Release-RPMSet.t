$|++;

use File::Path;
use Data::Dumper;

use Test::More;
BEGIN {
	my $rpm = `which rpm 2>/dev/null`;
	if ($? == 0) {
		plan tests => 26;
		use_ok('OpenNMS::Release::RPMPackage');
		use_ok('OpenNMS::Release::RPMSet');
	} else {
		plan skip_all => '`rpm` not found, skipping RPM tests.';
	}
};

rmtree("t/newrepo");

my $rpmset = OpenNMS::Release::RPMSet->new();
isa_ok($rpmset, 'OpenNMS::Release::RPMSet');

is(scalar(@{$rpmset->find_all()}), 0);

$rpmset->add(OpenNMS::Release::RPMPackage->new("t/repo/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm"));
$rpmset->add(OpenNMS::Release::RPMPackage->new("t/repo/stable/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm"));
$rpmset->add(OpenNMS::Release::RPMPackage->new("t/repo/stable/common/opennms/opennms-1.8.16-1.noarch.rpm"));

is(scalar(@{$rpmset->find_all()}), 3);
is(scalar(@{$rpmset->find_newest()}), 2);

is(scalar(@{$rpmset->find_by_name("iplike")}), 2);
$rpm = $rpmset->find_newest_by_name("iplike");
ok(defined $rpm);
is($rpm->[0]->name, "iplike");
is($rpm->[0]->version, "2.0.2");

is(scalar(@{$rpmset->find_by_name("opennms")}), 1);
$rpm = $rpmset->find_newest_by_name("opennms");
ok(defined $rpm);
is($rpm->[0]->name, "opennms");
is($rpm->[0]->version, "1.8.16");

$rpmset->set();
is(scalar(@{$rpmset->find_all()}), 0);
$rpmset->set(OpenNMS::Release::RPMPackage->new("t/repo/bleeding/common/opennms/opennms-1.11.0-0.20111220.1.noarch.rpm"));
is(scalar(@{$rpmset->find_all()}), 1);
is($rpmset->find_all()->[0]->name, "opennms");

$rpm = OpenNMS::Release::RPMPackage->new("t/repo/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm");
$rpmset->set(OpenNMS::Release::RPMPackage->new("t/repo/stable/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm"));
ok($rpmset->is_obsolete($rpm));

$rpmset->add($rpm);
$rpmlist = $rpmset->find_obsolete();

is(scalar(@{$rpmlist}), 1);
is($rpmlist->[0]->version, "1.0.7");

$rpmset->set();
$rpmset->add(OpenNMS::Release::RPMPackage->new('t/repo/bleeding/rhel5/opennms/x86_64/iplike-1.0.7-1.x86_64.rpm'));
$rpmset->add(OpenNMS::Release::RPMPackage->new('t/repo/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm'));
$rpmset->add(OpenNMS::Release::RPMPackage->new('t/repo/stable/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm'));

is(scalar(@{$rpmset->find_all()}), 3);
is(scalar(@{$rpmset->find_newest()}), 2);

$rpmlist = $rpmset->find_newest();
is($rpmlist->[0]->arch, 'i386');
is($rpmlist->[0]->version, '2.0.2');
is($rpmlist->[1]->arch, 'x86_64');
is($rpmlist->[1]->version, '1.0.7');
