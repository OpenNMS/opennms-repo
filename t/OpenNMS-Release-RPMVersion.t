use Test::More;
BEGIN {
	my $rpmver = `which rpmver 2>/dev/null`;
	if ($? == 0) {
		plan tests => 15;
		use_ok('OpenNMS::Release::RPMVersion');
	} else {
		plan skip_all => '`rpmver` not found, skipping RPM tests.';
	}
};

my $one_oh_one     = OpenNMS::Release::RPMVersion->new('1.0', '1');
my $one_oh_two     = OpenNMS::Release::RPMVersion->new('1.0', '2');
my $two_oh_one     = OpenNMS::Release::RPMVersion->new('2.0', '1');
my $two_oh_two     = OpenNMS::Release::RPMVersion->new('2.0', '2');
my $two_oh_one_one = OpenNMS::Release::RPMVersion->new('2.0.1', '1');

is($one_oh_one->version, '1.0');
is($one_oh_one->release, '1');
is($one_oh_one->full_version, '0:1.0-1');

is($one_oh_one->compare_to($one_oh_two), -1);
is($one_oh_one->compare_to($one_oh_one), 0);
is($two_oh_one->compare_to($one_oh_one), 1);
is($two_oh_one_one->compare_to($two_oh_one), 1);
is($two_oh_one_one->compare_to($two_oh_two), 1);

my $release = OpenNMS::Release::RPMVersion->new('1.9.93', '1');
my $beta    = OpenNMS::Release::RPMVersion->new('1.9.93', '0.20111220.1');
my $beta2   = OpenNMS::Release::RPMVersion->new('1.9.93', '0.20111220.2');

is($release->compare_to($beta), 1);
is($release->compare_to($beta2), 1);
is($beta->compare_to($beta2), -1);

ok($release->equals($release));
ok($release->is_newer_than($beta));
ok($beta->is_older_than($beta2));
