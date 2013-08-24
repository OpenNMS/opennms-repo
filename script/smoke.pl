#!/usr/bin/perl -w

use strict;
use warnings;

use File::Basename;
use File::Find;
use File::ShareDir qw(:ALL);
use File::Spec;
use IO::Handle;
use POSIX;
use Proc::ProcessTable;

use OpenNMS::Release;

use vars qw(
	$SELENIUM_LOG

	$SCRIPT
	$XVFB_RUN
	$JAVA

	$SELENIUM_JAR
	$SELENIUM_HUB
	$SELENIUM_WEBDRIVER
);

END {
	if (defined $SELENIUM_HUB and $SELENIUM_HUB =~ /^\d+$/) {
		kill('TERM', $SELENIUM_HUB);
	}
	if (defined $SELENIUM_WEBDRIVER and $SELENIUM_WEBDRIVER =~ /^\d+$/) {
		kill('TERM', $SELENIUM_WEBDRIVER);
	}

	if (defined $SCRIPT and -x $SCRIPT) {
		my $uid = getpwnam('bamboo');
		if (not defined $uid) {
			$uid = getpwnam('opennms');
		}
		find(
			sub {
				chown($uid, $_);
			},
			dirname($SCRIPT)
		);
	}

	print "Finished.\n";
}

$SCRIPT = shift(@ARGV);
if (not defined $SCRIPT or $SCRIPT eq '' or not -x $SCRIPT) {
	print STDERR "usage: $0 <script-to-run>\n";
	exit(1);
}

$SELENIUM_LOG = IO::Handle->new();
open($SELENIUM_LOG, '>', '/tmp/selenium.log') or die "Failed to open /tmp/selenium.log for writing: $!\n";

$ENV{'DISPLAY'} = ':99';

if (not exists $ENV{'JAVA_HOME'} or not -d $ENV{'JAVA_HOME'}) {
	die "\$JAVA_HOME is not set, or not valid!";
}

$JAVA = File::Spec->catfile($ENV{'JAVA_HOME'}, 'bin', 'java');

chomp($XVFB_RUN = `which xvfb-run`);
if (not defined $XVFB_RUN or $XVFB_RUN eq "" or ! -x $XVFB_RUN) {
	die "Unable to locate xvfb-run!\n";
}

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

#print "hub = $SELENIUM_HUB, webdriver = $SELENIUM_WEBDRIVER\n";

my $dir = dirname($SCRIPT);
chdir($dir);
my $result = system($XVFB_RUN, $SCRIPT);
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
