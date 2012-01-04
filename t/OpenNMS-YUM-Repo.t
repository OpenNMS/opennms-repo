# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl OpenNMS-YUM.t'

$|++;

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use File::Path;
use Data::Dumper;
use OpenNMS::YUM::RPM;
use Test::More tests => 37;
BEGIN {
	use_ok('OpenNMS::YUM::Repo');
};
import OpenNMS::YUM::Repo::RPMSet;

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

rmtree("t/newrepo");

my $stable_ro = OpenNMS::YUM::Repo->new("t/repo", "stable", "common");
isa_ok($stable_ro, 'OpenNMS::YUM::Repo');

is($stable_ro->base, "t/repo");
is($stable_ro->release, "stable");
is($stable_ro->platform, "common");

my $stable_copy = $stable_ro->copy("t/newrepo");
ok(-d "t/newrepo");
ok(-d "t/newrepo/stable/common");
ok(-f "t/newrepo/stable/common/opennms/opennms-1.8.16-1.noarch.rpm");

$stable_copy->delete();
ok(! -d "t/newrepo/stable/common");

my $stable_common   = OpenNMS::YUM::Repo->new("t/repo", "stable", "common")->copy("t/newrepo");
my $stable_rhel5    = OpenNMS::YUM::Repo->new("t/repo", "stable", "rhel5")->copy("t/newrepo");
my $bleeding_common = OpenNMS::YUM::Repo->new("t/repo", "bleeding", "common")->copy("t/newrepo");
my $bleeding_rhel5  = OpenNMS::YUM::Repo->new("t/repo", "bleeding", "rhel5")->copy("t/newrepo");

my $rpmlist = $stable_common->find_all_rpms();
is(scalar(@{$rpmlist}), 1);

my $rpm = $rpmlist->[0];
isa_ok($rpm, 'OpenNMS::YUM::RPM');
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

$rpm = $bleeding_common->find_newest_rpm_by_name("opennms");
is($rpm->name, "opennms");
is($rpm->version, "1.11.0");

$rpmlist = $stable_rhel5->find_all_rpms();
is(scalar(@{$rpmlist}), 1);

$rpm = $rpmlist->[0];
$bleeding_rhel5->share_rpm($stable_rhel5, $rpm);
ok(-l "t/newrepo/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm");

$rpmlist = $bleeding_rhel5->find_newest_rpms();
is(scalar(@{$rpmlist}), 1);

$rpmlist = $bleeding_rhel5->find_all_rpms();
is(scalar(@{$rpmlist}), 2);

$bleeding_rhel5->share_rpm($stable_rhel5, $rpm);
ok(-l "t/newrepo/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm");

$rpmlist = $bleeding_rhel5->find_all_rpms();
is(scalar(@{$rpmlist}), 2);

##### RPMSet Tests #####

my $rpmset = OpenNMS::YUM::Repo::RPMSet->new();
isa_ok($rpmset, 'OpenNMS::YUM::Repo::RPMSet');

is(scalar(@{$rpmset->find_all()}), 0);

$rpmset->add(OpenNMS::YUM::RPM->new("t/newrepo/bleeding/rhel5/opennms/i386/iplike-1.0.7-1.i386.rpm"));
$rpmset->add(OpenNMS::YUM::RPM->new("t/newrepo/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm"));
$rpmset->add(OpenNMS::YUM::RPM->new("t/newrepo/stable/common/opennms/opennms-1.8.16-1.noarch.rpm"));

is(scalar(@{$rpmset->find_all()}), 3);
is(scalar(@{$rpmset->find_newest()}), 2);

is(scalar(@{$rpmset->find_by_name("iplike")}), 2);
is($rpmset->find_newest_by_name("iplike")->name, "iplike");
is($rpmset->find_newest_by_name("iplike")->version, "2.0.2");

is(scalar(@{$rpmset->find_by_name("opennms")}), 1);
is($rpmset->find_newest_by_name("opennms")->name, "opennms");
is($rpmset->find_newest_by_name("opennms")->version, "1.8.16");

$rpmset->set();
is(scalar(@{$rpmset->find_all()}), 0);
$rpmset->set(OpenNMS::YUM::RPM->new("t/newrepo/bleeding/common/opennms/opennms-1.11.0-0.20111220.1.noarch.rpm"));
is(scalar(@{$rpmset->find_all()}), 1);
is($rpmset->find_all()->[0]->name, "opennms");

$stable_common->delete;
$stable_rhel5->delete;
$bleeding_common->delete;
$bleeding_rhel5->delete;
