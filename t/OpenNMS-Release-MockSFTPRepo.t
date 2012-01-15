$|++;

use Cwd;
use File::Path;
use Data::Dumper;
use Test::More tests => 22;

# t/packages/source/foo-1.0-2.tar.bz2
# t/packages/source/foo-2.0.tar.bz2
# t/packages/source/test-1.0-2.tar.gz
# t/packages/source/test-1.0.tgz
# t/packages/source/test-1.1-1.tar.gz
# t/packages/source/test-package-with-multiple-name-sections-1.0-1.tar.bz2
# t/packages/source/test.tgz

my $class = 'OpenNMS::Release::MockSFTPRepo';

use_ok($class);
use_ok('OpenNMS::Release::FileRepo');

my $t = Cwd::abs_path('t');
my ($a, $b);

reset_repos();
my $packages = $a->find_all_packages();

$a->share_all_packages($b);

my $package = $a->find_newest_package_by_name('test', 'tarball');
ok($package);
is($package->version->version, '1.1');

$packages = $a->find_all_packages();
is(scalar(@$packages), 36);

$package = OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0.tgz");
$a->install_package($package);

$packages = $a->find_all_packages();
is(scalar(@$packages), 37);

my $deleted = $a->delete_obsolete_packages();
is($deleted, 33);

$packages = $a->find_all_packages();
is(scalar(@$packages), 4);

# copy, replace, create_temporary not supported
eval {
	$a->copy;
};
ok($@, $@);

eval {
	$a->replace;
};
ok($@, $@);

eval {
	$a->create_temporary;
};
ok($@, $@);

reset_repos();

my $new = $a->begin();
is($new->path, '/home/frs/project/o/op/opennms/OpenNMS-Snapshots');
$new->share_all_packages($b);

$package = $new->find_newest_package_by_name('test', 'tarball');
ok($package);
is($package->version->version, '1.1');
$package = $a->find_newest_package_by_name('test', 'tarball');
ok($package);
is($package->version->version, '1.1');

$packages = $new->find_all_packages();
is(scalar(@$packages), 36);

$package = OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0.tgz");
$new->install_package($package);

$packages = $new->find_all_packages();
is(scalar(@$packages), 37);

$deleted = $new->delete_obsolete_packages();
is($deleted, 33);

$packages = $new->find_all_packages();
is(scalar(@$packages), 4);

$new->abort();

$packages = $new->find_all_packages();
is(scalar(@$packages), 33);

reset_repos();

$new = $a->begin();
$new->share_all_packages($b);
$new->commit();

$packages = $a->find_all_packages();
is(scalar(@$packages), 36);

sub reset_repos {
	$a = $class->new('frs.sourceforge.net', '/home/frs/project/o/op/opennms/OpenNMS-Snapshots');
	$b = OpenNMS::Release::FileRepo->new("$t/packages/source");
}
