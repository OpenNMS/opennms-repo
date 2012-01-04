# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl OpenNMS-YUM.t'

$|++;

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 24;
BEGIN { use_ok('OpenNMS::YUM::RPM') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my ($rpm);

$rpm = OpenNMS::YUM::RPM->new();
is($rpm, undef, "Check for invalid RPM when no path is provided.");

$rpm = OpenNMS::YUM::RPM->new("t/repo/bleeding/common/opennms/opennms-1.11.0-0.20111220.1.noarch.rpm");
isa_ok($rpm, 'OpenNMS::YUM::RPM');

is($rpm->name,    'opennms',      'Package name is "opennms".');
is($rpm->epoch,   undef,          'Epoch should be undefined.');
is($rpm->version, '1.11.0',       'Version should be 1.11.0.');
is($rpm->release, '0.20111220.1', 'Release should be snapshot.');
is($rpm->arch,    'noarch',       'Architecture should be "noarch".');

ok($rpm->is_in_repo('t'), 'RPM should be in t/.');
ok($rpm->is_in_repo('t/../t'), 'is_in_path should handle relative paths');

$olderrpm = OpenNMS::YUM::RPM->new("t/repo/stable/common/opennms/opennms-1.8.16-1.noarch.rpm");

is($rpm->compare_to($olderrpm), 1);
is($olderrpm->compare_to($rpm), -1);
is($rpm->compare_to($olderrpm, 0), 1);
is($olderrpm->compare_to($rpm, 0), -1);
ok($rpm->is_newer_than($olderrpm));
ok(!$rpm->is_older_than($olderrpm));
ok($olderrpm->is_older_than($rpm));
ok(!$olderrpm->is_newer_than($rpm));
ok($rpm->equals($rpm));
ok(!$rpm->equals($olderrpm));


$olderrpm->copy("t/test.rpm");
ok(-e 't/test.rpm');
unlink "t/test.rpm";

$olderrpm->copy("t");
ok(-e 't/opennms-1.8.16-1.noarch.rpm');
unlink "t/opennms-1.8.16-1.noarch.rpm";


$rpm->symlink("t/test2.rpm");
ok(-l "t/test2.rpm");
unlink "t/test2.rpm";

$rpm->symlink("t");
ok(-l "t/opennms-1.11.0-0.20111220.1.noarch.rpm");
unlink("t/opennms-1.11.0-0.20111220.1.noarch.rpm");
