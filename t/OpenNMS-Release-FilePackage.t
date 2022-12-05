use strict;
use warnings;

use Cwd;
use Test::More tests => 70;

use_ok('OpenNMS::Release::FilePackage');

my ($t, $tarball, $older_tarball, $newer_tarball);

$t = Cwd::abs_path('t');

# newer_than is based on t/packages/source/test-1.0-2.tar.gz
# undef = throw exception

my $test_parsing = {
	"$t/packages/source/foo-1.0-2.tar.bz2"
		=> {
			name        => 'foo',
			version     => '1.0',
			release     => '2',
			extension   => 'tar.bz2',
			compression => 'bzip2',
			newer_than  => undef,
		},
	"$t/packages/source/foo-2.0.tar.bz2"
		=> {
			name        => 'foo',
			version     => '2.0',
			release     => 0,
			extension   => 'tar.bz2',
			compression => 'bzip2',
			newer_than  => undef,
		},
	"$t/packages/source/test-1.0-2.tar.gz"
		=> {
			name        => 'test',
			version     => '1.0',
			release     => '2',
			extension   => 'tar.gz',
			compression => 'gzip',
			newer_than  => 0,
		},
	"$t/packages/source/test-1.0.tgz"
		=> {
			name        => 'test',
			version     => '1.0',
			release     => 0,
			extension   => 'tgz',
			compression => 'gzip',
			newer_than  => 0,
		},
	"$t/packages/source/test-1.1-1.tar.gz"
		=> {
			name        => 'test',
			version     => '1.1',
			release     => '1',
			extension   => 'tar.gz',
			compression => 'gzip',
			newer_than  => 1,
		},
	"$t/packages/source/test-package-with-multiple-name-sections-1.0-1.tar.bz2"
		=> {
			name        => 'test-package-with-multiple-name-sections',
			version     => '1.0',
			release     => '1',
			extension   => 'tar.bz2',
			compression => 'bzip2',
			newer_than  => undef,
		},
	"$t/packages/source/test.tgz"
		=> {
			name        => 'test',
			version     => 0,
			release     => 0,
			extension   => 'tgz',
			compression => 'gzip',
			newer_than  => 0,
		},
};

$tarball = OpenNMS::Release::FilePackage->new();
is($tarball, undef, "Check for invalid tarball when no path is provided.");

$newer_tarball = OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0-2.tar.gz");
isa_ok($newer_tarball, 'OpenNMS::Release::FilePackage');

is($newer_tarball->name,             'test',    'Package name is "test".');
is($newer_tarball->version->epoch,   undef,     'Epoch should be undefined.');
is($newer_tarball->version->version, '1.0',     'Version should be 1.0.');
is($newer_tarball->version->release, '2',       'Release should be snapshot.');
is($newer_tarball->arch,             'tarball', 'Architecture should be "tarball".');

is($newer_tarball->is_newer_than($newer_tarball), 0);

for my $tarname (sort keys %$test_parsing) {
	$tarball = OpenNMS::Release::FilePackage->new($tarname);

	my $attributes = $test_parsing->{$tarname};

	is($tarball->name,             $attributes->{name},        "$tarname name");
	is($tarball->version->epoch,   undef,                      "$tarname epoch");
	is($tarball->version->version, $attributes->{version},     "$tarname version");
	is($tarball->version->release, $attributes->{release},     "$tarname release");
	is($tarball->extension,        $attributes->{extension},   "$tarname extension");
	is($tarball->compression,      $attributes->{compression}, "$tarname compression");

	my $newer_than = undef;
	eval {
		$newer_than = $tarball->is_newer_than($newer_tarball);
	};
	if (not defined $attributes->{newer_than}) {
		ok($@, "$tarname newer_than");
	} else {
		is($newer_than, $attributes->{newer_than}, "$tarname newer_than");
	}
}

$older_tarball = OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0.tgz");

is($newer_tarball->compare_to($older_tarball), 1);
is($older_tarball->compare_to($newer_tarball), -1);
ok($newer_tarball->is_newer_than($older_tarball));
ok(!$newer_tarball->is_older_than($older_tarball));
ok($older_tarball->is_older_than($newer_tarball));
ok(!$older_tarball->is_newer_than($newer_tarball));
ok($newer_tarball->equals($newer_tarball));
ok(!$newer_tarball->equals($older_tarball));

$older_tarball->copy("$t/blah.tar.gz");
ok(-e "$t/blah.tar.gz");
unlink "$t/blah.tar.gz";

$older_tarball->copy("$t");
ok(-e "$t/test-1.0.tgz");
unlink "$t/test-1.0.tgz";

$newer_tarball->symlink("$t/blah2.tar.gz");
ok(-l "$t/blah2.tar.gz");
unlink "$t/blah2.tar.gz";

$newer_tarball->symlink("$t");
ok(-l "$t/test-1.0-2.tar.gz");
unlink("$t/test-1.0-2.tar.gz");
