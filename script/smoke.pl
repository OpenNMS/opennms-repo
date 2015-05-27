#!/usr/bin/perl -w

use strict;
use warnings;

use Config qw();
use Cwd qw(abs_path);
use File::Basename;
use File::Find;
use File::Path;
use File::ShareDir qw(:ALL);
use File::Spec;
use IO::Handle;
use POSIX;
use Proc::ProcessTable;
use version;

use OpenNMS::Release;

use vars qw(
	$SCRIPT
	$XVFB_RUN
	$JAVA

	$NON_DESTRUCTIVE
);

END {
	clean_up();
}

print $0 . ' ' . version->new($OpenNMS::Release::VERSION) . "\n";

$ENV{'PATH'} = $ENV{'PATH'} . $Config::Config{path_sep} . '/usr/sbin' . $Config::Config{path_sep} . '/sbin';

$SCRIPT = shift(@ARGV);
if (not defined $SCRIPT or $SCRIPT eq '' or not -x $SCRIPT) {
	print STDERR "usage: $0 <script-to-run>\n";
	exit(1);
}

delete $ENV{'DISPLAY'};

if (not exists $ENV{'JAVA_HOME'} or not -d $ENV{'JAVA_HOME'}) {
	die "\$JAVA_HOME is not set, or not valid!";
}

$JAVA = File::Spec->catfile($ENV{'JAVA_HOME'}, 'bin', 'java');

chomp($XVFB_RUN = `which xvfb-run`);
if (not defined $XVFB_RUN or $XVFB_RUN eq "" or ! -x $XVFB_RUN) {
	die "Unable to locate xvfb-run!\n";
}

$NON_DESTRUCTIVE = (exists $ENV{'NON_DESTRUCTIVE'} and $ENV{'NON_DESTRUCTIVE'});

my $m2_repo = File::Spec->catdir($ENV{'HOME'}, '.m2', 'repository');
if ($NON_DESTRUCTIVE) {
	print "Skipping repository cleanup, \$NON_DESTRUCTIVE is set.\n";
} else {
	rmtree($m2_repo);
}

my $dir = dirname($SCRIPT);
chdir($dir);
my $result = system($XVFB_RUN, '--wait=10', '--server-args=-screen 0 1920x1080x24', '--server-num=80', '--auto-servernum', '--listen-tcp', $SCRIPT);
my $ret = $? >> 8;

exit($ret);

sub clean_up {
	# make sure everything is owned by non-root
	if (defined $SCRIPT and -x $SCRIPT) {
		my $smokedir = dirname(abs_path($SCRIPT));
		my $rootdir = dirname($smokedir);

		if ($NON_DESTRUCTIVE) {
			print "- skipping sync and delete, \$NON_DESTRUCTIVE is set...\n";
		} else {
			my $surefiredir = File::Spec->catdir($smokedir, 'target', 'surefire-reports');
			if (-d $surefiredir) {
				my $top_surefiredir = File::Spec->catdir($rootdir, 'target', 'surefire-reports');
				print "- syncing surefire-reports to top-of-tree... ";
				mkpath($top_surefiredir);
				if (system('rsync', '-ar', '--delete', $surefiredir . '/', $top_surefiredir . '/') == 0) {
					print "done\n";
	
					my $relative_script = File::Spec->abs2rel($SCRIPT, $rootdir);
					print "- deleting remaining files... ";
					my @remove;
					find(
						{
							bydepth => 1,
							wanted => sub {
								my $name = $File::Find::name;
								my $relative = File::Spec->abs2rel($name, $rootdir);
								return if ($relative =~ /^target/);
								return if ($relative eq $relative_script);
	
								push(@remove, $name);
							}
						},
						$rootdir
					);
	
					for my $file (@remove) {
						if (-d $file) {
							rmdir($file);
						} else {
							unlink($file);
						}
					}
					print "done\n";
				} else {
					print "failed\n";
				}
			}
		}

		print "- fixing ownership of $rootdir... ";
		my $uid = getpwnam('bamboo');
		if (not defined $uid) {
			$uid = getpwnam('opennms');
		}
		my $gid = getgrnam('bamboo');
		if (not defined $gid) {
			$gid = getgrnam('opennms');
		}
		if (defined $uid and defined $gid) {
			find(
				sub {
					chown($uid, $gid, $File::Find::name);
				},
				$rootdir
			);
			print "done\n";
		} else {
			print "unable to determine proper owner\n";
		}

	}

}
