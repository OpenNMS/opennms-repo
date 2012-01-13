$|++;

use Cwd;
use Test::More;
BEGIN {
	my $rpm = `which rpm 2>/dev/null`;
	if ($? == 0) {
		plan tests => 20;
		use_ok('OpenNMS::Release::RPMPackage');
	} else {
		plan skip_all => '`rpm` not found, skipping RPM tests.';
	}
};

my $t = Cwd::abs_path("t");
my ($rpm);

$rpm = OpenNMS::Release::RPMPackage->new();
is($rpm, undef, "Check for invalid RPM when no path is provided.");

$rpm = OpenNMS::Release::RPMPackage->new("$t/packages/rpm/bleeding/common/opennms/opennms-1.11.0-0.20111220.1.noarch.rpm");
isa_ok($rpm, 'OpenNMS::Release::RPMPackage');

is($rpm->name,             'opennms',      'Package name is "opennms".');
is($rpm->version->epoch,   undef,          'Epoch should be undefined.');
is($rpm->version->version, '1.11.0',       'Version should be 1.11.0.');
is($rpm->version->release, '0.20111220.1', 'Release should be snapshot.');
is($rpm->arch,             'noarch',       'Architecture should be "noarch".');

$olderrpm = OpenNMS::Release::RPMPackage->new("$t/packages/rpm/stable/common/opennms/opennms-1.8.16-1.noarch.rpm");

is($rpm->compare_to($olderrpm), 1);
is($olderrpm->compare_to($rpm), -1);
ok($rpm->is_newer_than($olderrpm));
ok(!$rpm->is_older_than($olderrpm));
ok($olderrpm->is_older_than($rpm));
ok(!$olderrpm->is_newer_than($rpm));
ok($rpm->equals($rpm));
ok(!$rpm->equals($olderrpm));


$olderrpm->copy("$t/test.rpm");
ok(-e 't/test.rpm');
unlink "$t/test.rpm";

$olderrpm->copy("$t");
ok(-e 't/opennms-1.8.16-1.noarch.rpm');
unlink "$t/opennms-1.8.16-1.noarch.rpm";


$rpm->symlink("$t/test2.rpm");
ok(-l "$t/test2.rpm");
unlink "$t/test2.rpm";

$rpm->symlink("$t");
ok(-l "$t/opennms-1.11.0-0.20111220.1.noarch.rpm");
unlink("$t/opennms-1.11.0-0.20111220.1.noarch.rpm");
