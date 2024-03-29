#!/usr/bin/perl -w

use 5.026;

use strict;
use warnings;

use File::Spec;
use Getopt::Long qw(:config gnu_getopt);
use version;

use OpenNMS::Release;
use OpenNMS::Release::FilePackage 2.6.3;
use OpenNMS::Release::SFTPRepo 2.6.3;

print $0 . ' ' . version->new($OpenNMS::Release::VERSION) . "\n";

my $help   = 0;
my $result = GetOptions(
	"h|help"     => \$help,
);

my $release = shift @ARGV;
my @files   = @ARGV;

if ($help or not @files) {
	usage();
}

my $repo = OpenNMS::Release::SFTPRepo->new('frs.sourceforge.net', File::Spec->catdir('/home/frs/project/o/op/opennms/OpenNMS-Snapshots', $release))->begin();
for my $file (@files) {
	my $package = OpenNMS::Release::FilePackage->new(Cwd::abs_path($file));
	print "- installing ", $package->to_string, "\n";
	$repo->install_package($package);
}
$repo->commit();

$repo = OpenNMS::Release::SFTPRepo->new('frs.sourceforge.net', File::Spec->catdir('/home/frs/project/o/op/opennms/OpenNMS-Snapshots', $release));
$repo->delete_obsolete_packages();

sub usage {
	print STDERR <<END;
usage: $0 <release> <tarball1..tarballN>

	-h       This help.

END
	exit 1;
}
