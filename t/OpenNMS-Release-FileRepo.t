$|++;

use Cwd;
use File::Path;
use Data::Dumper;
use Test::More tests => 45;

# t/packages/source/foo-1.0-2.tar.bz2
# t/packages/source/foo-2.0.tar.bz2
# t/packages/source/test-1.0-2.tar.gz
# t/packages/source/test-1.0.tgz
# t/packages/source/test-1.1-1.tar.gz
# t/packages/source/test-package-with-multiple-name-sections-1.0-1.tar.bz2
# t/packages/source/test.tgz

use_ok('OpenNMS::Release::FileRepo');

my $t = Cwd::abs_path("t");

reset_repos();

my $source_ro = OpenNMS::Release::FileRepo->new("$t/packages/source");
isa_ok($source_ro, 'OpenNMS::Release::FileRepo');

is($source_ro->base, "$t/packages/source");

my $stable_copy = $source_ro->copy("$t/testpackages/source");
ok(-d "$t/testpackages/source");
ok(-f "$t/testpackages/source/test-1.0.tgz");

$stable_copy->delete();
ok(! -d "$t/testpackages/source");

my ($a, $b);

reset_repos();

my $packagelist = $a->find_all_packages();
is(scalar(@{$packagelist}), 7);

my $package = $a->find_newest_package_by_name('test', 'tarball');
isa_ok($package, 'OpenNMS::Release::FilePackage');
is($package->name, 'test');

$packagelist = $b->find_all_packages();
is(scalar(@{$packagelist}), 0);

$b->install_package($package);
ok(-f "$t/testpackages/new/test-1.1-1.tar.gz");

$packagelist = $b->find_all_packages();
is(scalar(@{$packagelist}), 1);

# make sure that we don't get duplicate entries in the package set if we
# install an existing package
$b->install_package($package);

$packagelist = $b->find_all_packages();
is(scalar(@{$packagelist}), 1);

$package = $b->find_newest_package_by_name('test', 'tarball');
is($package->name, 'test');
is($package->version->version, '1.1');

$packagelist = $a->find_all_packages();
is(scalar(@{$packagelist}), 7);

$package = $a->find_newest_package_by_name('test-package-with-multiple-name-sections', 'tarball');
$b->share_package($a, $package);
ok(-f "$t/testpackages/new/test-package-with-multiple-name-sections-1.0-1.tar.bz2" and not -l "$t/testpackages/new/test-package-with-multiple-name-sections-1.0-1.tar.bz2");

$packagelist = $b->find_newest_packages();
is(scalar(@{$packagelist}), 2);

$packagelist = $b->find_all_packages();
is(scalar(@{$packagelist}), 2);

$b->install_package(OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0.tgz"));

$b->share_package($a, $package);
ok(-f "$t/testpackages/new/test-package-with-multiple-name-sections-1.0-1.tar.bz2" and not -l "$t/testpackages/new/test-package-with-multiple-name-sections-1.0-1.tar.bz2");

$packagelist = $b->find_all_packages();
is(scalar(@{$packagelist}), 3);

$packagelist = $b->find_obsolete_packages();

is(scalar(@{$packagelist}), 1);
is($packagelist->[0]->version->version, "1.0");
is($packagelist->[0]->version->release, "0");

# subroutine says to not delete any
is($b->delete_obsolete_packages(sub { return 0 }), 0);
ok(-e "$t/testpackages/new/test-1.0.tgz");

# delete any obsolete by default
is($b->delete_obsolete_packages(), 1);
ok(! -e "$t/testpackages/new/test-1.0.tgz");

is($b->delete_obsolete_packages(sub { $_[0]->name ne 'test' }), 0);

reset_repos();

$b->install_package(OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0.tgz"));
$b->share_all_packages($a);

$packagelist = $b->find_all_packages();
is(scalar(@{$packagelist}), 4);

$packagelist = $b->find_newest_packages();
is(scalar(@{$packagelist}), 3);

$packagelist = $b->find_obsolete_packages();
is(scalar(@{$packagelist}), 1);
is($packagelist->[0]->name, 'test');
is($packagelist->[0]->version->version, '1.0');
is($packagelist->[0]->version->release, '0');

# this should delete the old test-1.0.tgz
is($b->delete_obsolete_packages(), 1);
$package = $b->find_newest_package_by_name('test', 'tarball');
is($package->version->version, '1.1');

$b->delete;
mkpath($b->path);

my $copy = $b->copy("$t/copy");
$package = OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0.tgz");
$copy->install_package($package);
$b = $copy->replace($b);
ok(! -d "$t/copy");
$package = $b->find_newest_package_by_name('test', 'tarball');
ok(defined $package);
is($package->version->version, '1.0');

$a->delete;
$b->delete;

# test begin/commit

reset_repos();

ok(! -e "$t/testpackages/new/test-1.0.tgz");
my $temp = $b->begin();
$temp->install_package(OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0.tgz"));
$temp->commit();
ok(-f "$t/testpackages/new/test-1.0.tgz");

# test begin/abort

reset_repos();

ok(! -e "$t/testpackages/new/test-1.0.tgz");
$temp = $b->begin();
$temp->install_package(OpenNMS::Release::FilePackage->new("$t/packages/source/test-1.0.tgz"));
$temp->abort();
ok(! -e "$t/testpackages/new/test-1.0.tgz");

# test begin inside begin

reset_repos();

$temp = $a->begin();
eval {
	$temp = $temp->begin();
};
ok(defined $@);

sub reset_repos {
	rmtree("$t/testpackages");
	$a = OpenNMS::Release::FileRepo->new("$t/packages/source")->copy("$t/testpackages/source");
	mkpath("$t/testpackages/new");
	$b = OpenNMS::Release::FileRepo->new("$t/testpackages/new");
}

