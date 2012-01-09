use Test::More;
BEGIN {
	my $dpkg = `which dpkg 2>/dev/null`;
	if ($? == 0) {
		plan tests => 18;
		use_ok('OpenNMS::Release::DebVersion');
	} else {
		plan skip_all => '`dpkg` not found, skipping Debian tests.';
	}
};

my $one_oh_one     = OpenNMS::Release::DebVersion->new('1.0', '1');
my $one_oh_two     = OpenNMS::Release::DebVersion->new('1.0', '2');
my $two_oh_one     = OpenNMS::Release::DebVersion->new('2.0', '1');
my $two_oh_two     = OpenNMS::Release::DebVersion->new('2.0', '2');
my $two_oh_one_one = OpenNMS::Release::DebVersion->new('2.0.1', '1');
my $epoch_one      = OpenNMS::Release::DebVersion->new('1.0', '0', '1');

is($one_oh_one->version, '1.0');
is($one_oh_one->release, '1');
is($one_oh_one->full_version, '0:1.0-1');

is($one_oh_one->compare_to($one_oh_two), -1);
is($one_oh_one->compare_to($one_oh_one), 0);
is($two_oh_one->compare_to($one_oh_one), 1);
is($two_oh_one_one->compare_to($two_oh_one), 1);
is($two_oh_one_one->compare_to($two_oh_two), 1);
is($epoch_one->compare_to($two_oh_one_one), 1);

my $release = OpenNMS::Release::DebVersion->new('1.9.93', '1');
my $beta    = OpenNMS::Release::DebVersion->new('1.9.93', '0.20111220.1');
my $beta2   = OpenNMS::Release::DebVersion->new('1.9.93', '0.20111220.2');
my $epoch   = OpenNMS::Release::DebVersion->new('1.9.93', '0', '1');

is($release->compare_to($beta), 1);
is($release->compare_to($beta2), 1);
is($beta->compare_to($beta2), -1);

ok($release->equals($release));
ok($release->is_newer_than($beta));
ok($beta->is_older_than($beta2));
ok($epoch->is_newer_than($release));
ok($epoch->is_newer_than($beta2));
