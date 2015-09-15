$|++;

use strict;
use warnings;

use Cwd;
use File::Path;
use Data::Dumper;
use Test::More skip_all => "only for one-time testing with a real repo";
#use Test::More tests => 22;

# t/packages/source/foo-1.0-2.tar.bz2
# t/packages/source/foo-2.0.tar.bz2
# t/packages/source/test-1.0-2.tar.gz
# t/packages/source/test-1.0.tgz
# t/packages/source/test-1.1-1.tar.gz
# t/packages/source/test-package-with-multiple-name-sections-1.0-1.tar.bz2
# t/packages/source/test.tgz

my $class = 'OpenNMS::Release::SFTPRepo';

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
is(scalar(@$packages), 3);

$package = OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0.tgz");
$a->install_package($package);

$packages = $a->find_all_packages();
is(scalar(@$packages), 4);

my $deleted = $a->delete_obsolete_packages();
is($deleted, 1);

$packages = $a->find_all_packages();
is(scalar(@$packages), 3);

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
is(scalar(@$packages), 3);

$package = OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0.tgz");
$new->install_package($package);

$packages = $new->find_all_packages();
is(scalar(@$packages), 4);

$deleted = $new->delete_obsolete_packages();
is($deleted, 1);

$packages = $new->find_all_packages();
is(scalar(@$packages), 3);

$new->abort();

$packages = $new->find_all_packages();
is(scalar(@$packages), 3);

reset_repos();

$new = $a->begin();
$new->share_all_packages($b);
$new->commit();

$packages = $a->find_all_packages();
is(scalar(@$packages), 3);

sub reset_repos {
	$a = $class->new({ host => 'frs.sourceforge.net', base => '/home/frs/project/o/op/opennms/OpenNMS-Snapshots' });
	$b = OpenNMS::Release::FileRepo->new({ base => "$t/packages/source" });
}
