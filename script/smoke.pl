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
	$SELENIUM_LOG

	$SCRIPT
	$XVFB_RUN
	$JAVA

	$NON_DESTRUCTIVE

	$SELENIUM_JAR
	$SELENIUM_HUB
	$SELENIUM_WEBDRIVER
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

$SELENIUM_LOG = IO::Handle->new();
open($SELENIUM_LOG, '>', '/tmp/selenium.log') or die "Failed to open /tmp/selenium.log for writing: $!\n";

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

update_selenium_pids();

$SELENIUM_JAR = get_selenium_jar();

if (not defined $SELENIUM_JAR) {
	die "Unable to locate selenium JAR file!";
}

if (not defined $SELENIUM_HUB) {
	print "Selenium hub is not running; starting:\n";
	$SELENIUM_HUB = nohup($JAVA, '-jar', $SELENIUM_JAR, '-role', 'hub');
	print "done.\n";
}

if (not defined $SELENIUM_WEBDRIVER) {
	print "Selenium webdriver is not running; starting:\n";
	$SELENIUM_WEBDRIVER = nohup($JAVA, '-jar', $SELENIUM_JAR, '-role', 'webdriver', '-hub', 'http://localhost:4444/grid/register', '-port', '5556');
	print "done.\n";
}

sleep(5);

update_selenium_pids();

my $m2_repo = File::Spec->catdir($ENV{'HOME'}, '.m2', 'repository');
if ($NON_DESTRUCTIVE) {
	print "Skipping repository cleanup, \$NON_DESTRUCTIVE is set.\n";
} else {
	rmtree($m2_repo);
}

my $dir = dirname($SCRIPT);
chdir($dir);
my $result = system($XVFB_RUN, '--server-args=-screen 0 1920x1080x24', '--server-num=80', '--auto-servernum', '--listen-tcp', $SCRIPT);
my $ret = $? >> 8;

exit($ret);

sub get_selenium_jar {
	my $dir = dist_dir('OpenNMS-Release');
	my $handle = IO::Handle->new();
	opendir($handle, $dir) or die "unable to open $dir for reading: $!\n";
	while (my $file = readdir($handle)) {
		if ($file =~ /selenium.*\.jar$/) {
			return File::Spec->catfile($dir, $file);
		}
	}
	return undef;
}

sub update_selenium_pids {
	my $proc = Proc::ProcessTable->new();
	for my $p (@{$proc->table}) {
		if ($p->cmndline =~ /selenium-server-standalone-.*.jar\s*.*-role\s*([^\s]*)/) {
			if ($1 eq 'webdriver') {
				$SELENIUM_WEBDRIVER = $p->pid;
			} elsif ($1 eq 'hub') {
				$SELENIUM_HUB = $p->pid;
			}
		}
	}
}

sub nohup {
	my @command = @_;
	local $SIG{'HUP'} = 'IGNORE';
	my $pid = fork;
	if ($pid) {
		# parent
		return $pid;
	} else {
		# child
		STDOUT->fdopen( $SELENIUM_LOG, 'w' ) or die "Failed to redirect STDOUT to /tmp/selenium.log: $!\n";
		STDERR->fdopen( $SELENIUM_LOG, 'w' ) or die "Failed to redirect STDOUT to /tmp/selenium.log: $!\n";
		setsid() or die "Cannot establish session id: $!\n";
		system(@command) == 0 or die "Failed to run @command: $!\n";
		exit(0);
	}
}

sub clean_up {
	if (defined $SELENIUM_HUB and $SELENIUM_HUB =~ /^\d+$/) {
		print "- stopping Selenium hub... ";
		kill('TERM', $SELENIUM_HUB);
		print "done\n";
	}
	if (defined $SELENIUM_WEBDRIVER and $SELENIUM_WEBDRIVER =~ /^\d+$/) {
		print "- stopping Selenium web driver... ";
		kill('TERM', $SELENIUM_WEBDRIVER);
		print "done\n";
	}

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
