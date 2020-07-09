#!/usr/bin/perl -w

use strict;
use warnings;

$|++;

use Cwd qw(abs_path cwd);
use File::Path qw(mkpath remove_tree);
use File::Spec;
use version;

use OpenNMS::Release;

use vars qw(
	$TARBALL
	$DESTPATH
);

my $dir = shift @ARGV || '.';
$DESTPATH = shift @ARGV || '/var/www';

opendir(DIR, $dir) or die "Unable to read from $dir: $!\n";
while (my $entry = readdir(DIR)) {
	if ($entry =~ /^(guide-all-.*|opennms-.*-docs|meridian-.*-docs)\.tar\.(gz|bz2)$/) {
		$TARBALL = abs_path(File::Spec->catfile($dir, $entry));
		last;
	}
}
closedir(DIR) or die "Unable to close $dir: $!\n";

if (defined $TARBALL) {
	print "* Found $TARBALL\n";
	my $v;
	if ($TARBALL =~ /guide-all/) {
		($v) = $TARBALL =~ /guide-all-([\d\.]+)/;
	} else {
		($v) = $TARBALL =~ /\w+-([\d\.]+)-docs/;
	}
	my ($year, $version) = $v =~ /^(\d+)\.([\d\.]+)$/;
	print "  - Year: $year\n";
	print "  - Version: $version\n";

	my ($extension) = $TARBALL =~ /\.(tar\.gz|tar\.bz2|tgz|tbz2)$/;

	my $cwd = cwd();
	my $tempdir = File::Spec->catdir($cwd, 'unpack');
	if (-d $tempdir) {
		remove_tree($tempdir) or die "Failed to remove temporary directory '$tempdir': $!\n";;
	}
	mkpath($tempdir) or die "Failed to create temporary directory '$tempdir': $!\n";

	print "* Unpacking '$TARBALL' into '$tempdir'... ";
	chdir($tempdir);
	if ($extension =~ /bz2/) {
		system('tar', '-xjf', $TARBALL) == 0 or die "Failed to unpack '$TARBALL' into '$tempdir': $!\n";
	} else {
		system('tar', '-xzf', $TARBALL) == 0 or die "Failed to unpack '$TARBALL' into '$tempdir': $!\n";
	}
	print "done.\n";

	for my $dir ('guide-admin', 'guide-concepts', 'guide-development', 'guide-doc', 'guide-install', 'guide-user') {
		copy_dirs(File::Spec->catdir($tempdir, $dir), File::Spec->catdir($DESTPATH, 'docs'), $year, $version, $dir);
	}
	copy_dirs(File::Spec->catdir($tempdir, 'releasenotes'), File::Spec->catdir($DESTPATH, 'releasenotes'), $year, $version, $dir);
} else {
	print "Unable to locate docs tarball in $dir\n";
	exit 1;
}

sub copy_dirs {
	my $from    = shift;
	my $to      = shift;
	my $year    = shift;
	my $version = shift;
	my $subdir  = shift;

	if (! -d $from) {
		print "* $from does not exist.  Skipping copy.\n";
		return;
	}

	my $dest = File::Spec->catdir($to, $year, $version, $subdir);
	if (! -d $dest) {
		mkpath($dest) or die "Failed to create '$dest' directory: $!\n";
	}

	for my $target ('index.html', 'index.pdf', 'images') {
		my $source = File::Spec->catdir($from, $target);
		if (-e $source) {
			print "* Copying '$source' to '$dest/'... ";
			system('rsync', '--no-compress', '-rl', '--exclude=*.adoc', $source, $dest . '/') == 0 or die "failed to copy files: $!\n";
			print "done.\n";
		}
	}

	my $yeardir = File::Spec->catdir($to, $year);
	opendir(DIR, $yeardir) or die "Failed to read directory '$yeardir': $!\n";
	my @entries = sort { $b <=> $a } grep {!/^(\.\.?|latest)$/} readdir(DIR);
	closedir(DIR) or die "Failed to close directory '$yeardir': $!\n";

	if (@entries > 0) {
		my $newest = File::Spec->catdir($to, $year, $entries[0]);
		my $latest = File::Spec->catdir($to, $year, 'latest');
		print "* Version directory $newest is the newest version in $year, linking to 'latest'.\n";
		if (-e $latest) {
			print "  - unlinking old 'latest' directory... ";
			unlink($latest) or die "Failed to unlink '$latest': $!\n";
			print "done.\n";
		}
		print "  - linking '$newest' to '$latest'... ";
		symlink($version, $latest) or die "Failed to link '$version' to '$latest': $!\n";
		print "done.\n";
	}
}
