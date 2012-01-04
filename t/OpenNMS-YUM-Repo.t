# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl OpenNMS-YUM.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Data::Dumper;
use OpenNMS::YUM::RPM;
use Test::More tests => 18;
BEGIN { use_ok('OpenNMS::YUM::Repo') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

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

my $rpmlist = $stable_common->get_rpms();
is(scalar(@$rpmlist), 1);

my $rpm = $rpmlist->[0];
isa_ok($rpm, 'OpenNMS::YUM::RPM');
is($rpm->name, 'opennms');

$bleeding_common->install_rpm($rpm, $rpm->relative_path($stable_common->abs_path));
ok(-f "t/newrepo/bleeding/common/opennms/opennms-1.8.16-1.noarch.rpm");

$rpmlist = $bleeding_common->get_rpms();
is(scalar(@$rpmlist), 2);

$rpm = $bleeding_common->find_newest_rpm_by_name("opennms");
is($rpm->name, "opennms");
is($rpm->version, "1.11.0");

$rpmlist = $stable_rhel5->get_rpms();
is(scalar(@$rpmlist), 1);

$rpm = $rpmlist->[0];
$bleeding_rhel5->share_rpm($stable_rhel5, $rpm);
ok(-l "t/newrepo/bleeding/rhel5/opennms/i386/iplike-2.0.2-1.i386.rpm");
