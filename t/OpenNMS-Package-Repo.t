$|++;

use File::Path;
use Data::Dumper;
use OpenNMS::Package::RPM;
use Test::More tests => 53;
BEGIN {
	use_ok('OpenNMS::Package::Repo');
};
import OpenNMS::Package::Repo::RPMSet;

rmtree("t/newrepo");

my $stable_ro = OpenNMS::Package::Repo->new("t/repo", "stable", "common");
isa_ok($stable_ro, 'OpenNMS::Package::Repo');

is($stable_ro->base, "t/repo");
is($stable_ro->release, "stable");
is($stable_ro->platform, "common");

my $stable_copy = $stable_ro->copy("t/newrepo");
ok(-d "t/newrepo");
ok(-d "t/newrepo/stable/common");
ok(-f "t/newrepo/stable/common/opennms/opennms-1.8.16-1.noarch.rpm");

$stable_copy->delete();
ok(! -d "t/newrepo/stable/common");

my $stable_common   = OpenNMS::Package::Repo->new("t/repo", "stable", "common")->copy("t/newrepo");
my $stable_rhel5    = OpenNMS::Package::Repo->new("t/repo", "stable", "rhel5")->copy("t/newrepo");
my $bleeding_common = OpenNMS::Package::Repo->new("t/repo", "bleeding", "common")->copy("t/newrepo");
my $bleeding_rhel5  = OpenNMS::Package::Repo->new("t/repo", "bleeding", "rhel5")->copy("t/newrepo");

my $rpmlist = $stable_common->find_all_rpms();
is(scalar(@{$rpmlist}), 1);

my $rpm = $rpmlist->[0];
isa_ok($rpm, 'OpenNMS::Package::RPM');
is($rpm->name, 'opennms');

$rpmlist = $bleeding_common->find_all_rpms();
is(scalar(@{$rpmlist}), 1);

$bleeding_common->install_rpm($rpm, "opennms");
ok(-f "t/newrepo/bleeding/common/opennms/opennms-1.8.16-1.noarch.rpm");

$rpmlist = $bleeding_common->find_all_rpms();
is(scalar(@{$rpmlist}), 2);

# make sure that we don't get duplicate entries in the RPM set if we
# install an existing RPM
$bleeding_common->install_rpm($rpm, "opennms");
$rpmlist = $bleeding_common->find_all_rpms();
is(scalar(@{$rpmlist}), 2);

($rpm) = $bleeding_common->find_newest_rpm_by_name("opennms", "noarch");
is($rpm->name, "opennms");
is($rpm->version, "1.11.0");

$rpmlist = $stable_rhel5->find_all_rpms();
is(scalar(@{$rpmlist}), 1);

$rpm = $rpmlist->[0];
$bleeding_rhel5->share_rpm($stable_rhel5, $rpm);
ok(-f "t/newrepo/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm" and not -l "t/newrepo/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm");

$rpmlist = $bleeding_rhel5->find_newest_rpms();
is(scalar(@{$rpmlist}), 2);

$rpmlist = $bleeding_rhel5->find_all_rpms();
is(scalar(@{$rpmlist}), 3);

$bleeding_rhel5->share_rpm($stable_rhel5, $rpm);
ok(-f "t/newrepo/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm" and not -l "t/newrepo/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm");

$rpmlist = $bleeding_rhel5->find_all_rpms();
is(scalar(@{$rpmlist}), 3);

##### RPMSet Tests #####

my $rpmset = OpenNMS::Package::Repo::RPMSet->new();
isa_ok($rpmset, 'OpenNMS::Package::Repo::RPMSet');

is(scalar(@{$rpmset->find_all()}), 0);

$rpmset->add(OpenNMS::Package::RPM->new("t/newrepo/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm"));
$rpmset->add(OpenNMS::Package::RPM->new("t/newrepo/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm"));
$rpmset->add(OpenNMS::Package::RPM->new("t/newrepo/stable/common/opennms/opennms-1.8.16-1.noarch.rpm"));

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
$rpmset->set(OpenNMS::Package::RPM->new("t/newrepo/bleeding/common/opennms/opennms-1.11.0-0.20111220.1.noarch.rpm"));
is(scalar(@{$rpmset->find_all()}), 1);
is($rpmset->find_all()->[0]->name, "opennms");

$rpm = OpenNMS::Package::RPM->new("t/newrepo/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm");
$rpmset->set(OpenNMS::Package::RPM->new("t/newrepo/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm"));
ok($rpmset->is_obsolete($rpm));

$rpmset->add($rpm);
$rpmlist = $rpmset->find_obsolete();

is(scalar(@{$rpmlist}), 1);
is($rpmlist->[0]->version, "1.0.7");

$rpmlist = $bleeding_rhel5->find_obsolete_rpms();

is(scalar(@{$rpmlist}), 1);
is($rpmlist->[0]->version, "1.0.7");

is($bleeding_rhel5->delete_obsolete_rpms(sub { return 0 }), 0);
ok(-e "t/newrepo/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm");
is($bleeding_rhel5->delete_obsolete_rpms(), 1);
ok(! -e "t/newrepo/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm");
is($bleeding_common->delete_obsolete_rpms(sub { $_[0]->name ne "opennms" }), 0);

$stable_rhel5->delete;
$bleeding_rhel5->delete;
$stable_rhel5   = OpenNMS::Package::Repo->new("t/repo", "stable", "rhel5")->copy("t/newrepo");
$bleeding_rhel5 = OpenNMS::Package::Repo->new("t/repo", "bleeding", "rhel5")->copy("t/newrepo");

$bleeding_rhel5->share_all_rpms($stable_rhel5);

$rpmlist = $bleeding_rhel5->find_all_rpms();
is(scalar(@{$rpmlist}), 3);

my $copy = $bleeding_rhel5->copy("t/copy");
$rpm = OpenNMS::Package::RPM->new("t/repo/stable/common/opennms/opennms-1.8.16-1.noarch.rpm");
$copy->install_rpm($rpm, "opennms");
$bleeding_rhel5 = $copy->replace($bleeding_rhel5);
ok(! -d "t/copy");
$rpm = $bleeding_rhel5->find_newest_rpm_by_name("opennms", "noarch");
ok(defined $rpm);
is($rpm->version, "1.8.16");

$stable_common->delete;
$stable_rhel5->delete;
$bleeding_common->delete;
$bleeding_rhel5->delete;
