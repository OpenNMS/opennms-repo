#!/usr/bin/perl -w

use strict;
use warnings;

$|++;

use Cwd qw(abs_path);
use File::Basename;
use File::Path;
use File::Slurp;
use File::Spec;
use Getopt::Long;
use Git;
use IO::Handle;

use vars qw(
	$SCRIPTDIR
	$GIT

	$CMD_BUILDTOOL

	$TYPE
	$ASSEMBLY_ONLY
	$BRANCH
	$TIMESTAMP
	$REVISION
	$REPOSITORY
	$PASSWORD
	$MICRO_REVISION

	$HELP
);

$SCRIPTDIR     = abs_path(dirname($0));
$CMD_BUILDTOOL = File::Spec->catfile($SCRIPTDIR, 'buildtool.pl');

$ASSEMBLY_ONLY = 0;
$BRANCH        = undef;
$HELP          = 0;
$TYPE          = undef;

GetOptions(
	"h|help"          => \$HELP,
	"t|type=s"        => \$TYPE,
	"a|assembly-only" => \$ASSEMBLY_ONLY,
	"b|branch=s"      => \$BRANCH,
) or die "Unable to parse command-line: $@\n";

if (not defined $BRANCH) {
	$BRANCH = get_branch();
}

$TIMESTAMP  = buildtool('get_stamp');
$REVISION   = buildtool('get_revision');
$REPOSITORY = get_repository();
$PASSWORD   = get_password();

my $scrubbed_branch = $BRANCH;
$scrubbed_branch =~ s/[^[:alnum:]]+/\./gs;
$scrubbed_branch =~ s/^\.+//;
$scrubbed_branch =~ s/\.+$//;

$MICRO_REVISION = $scrubbed_branch . '.' . $REVISION;
print <<END;
Type:       $TYPE
Branch:     $BRANCH
Timestamp:  $TIMESTAMP
Revision:   $MICRO_REVISION
Repository: $REPOSITORY

END

print "- cleaning up git and \$M2_REPO:\n";
clean_for_build();

if ($TYPE eq 'rpm') {
	make_rpm();
} elsif ($TYPE eq 'debian') {
	exit(1);
} elsif ($TYPE eq 'installer') {
	exit(1);
} else {
	usage("unknown build type: $TYPE");
}

buildtool('save');

sub make_rpm {
	my @command = (
		'./makerpm.sh',
		'-s', $PASSWORD,
		'-m', $TIMESTAMP,
		'-u', $MICRO_REVISION
	);

	if ($ASSEMBLY_ONLY) {
		push(@command, '-a');
	}

	system(@command) == 0 or die "Failed to run makerpm.sh: $!\n";
}

sub buildtool {
	my $command = shift;

	my $handle = IO::Handle->new();

	open($handle, '-|', "$CMD_BUILDTOOL 'snapshot-$TYPE' '$command' '$BRANCH'") or die "Unable to run $CMD_BUILDTOOL 'snapshot-$TYPE' '$command' '$BRANCH': $!\n";
	chomp(my $output = read_file($handle));
	close($handle) or die "Failed to close $CMD_BUILDTOOL call: $!\n";

	return $output;
}

sub clean_for_build {
	if (-d '.git') {
		my $git = Git->repository( Directory => '.' );
		$git->command('clean', '-fdx');
		$git->command('reset', '--hard', 'HEAD');
	}

	my $maven_dir = File::Spec->catdir($ENV{'HOME'}, '.m2', 'repository');
	rmtree($maven_dir);
}

sub get_branch {
	if (-d '.git') {
		my $git = Git->repository( Directory => '.' );
		try {
			my $ref = $git->command_oneline('symbolic-ref', 'HEAD');
			if (defined $ref and $ref =~ /refs/) {
				my ($ret) = $ref =~ /.*\/([^\/]*)$/;
				return $ret;
			}
		} catch {
		}
		die "Found a .git directory, but we were unable to determine the branch name!\n";
	} elsif (-r 'opennms-build-branch.txt') {
		chomp(my $branch_name = read_file('opennms-build-branch.txt'));
		return $branch_name;
	}

	die "No .git directory found, and opennms-build-branch.txt does not exist!  You must specify a branch name on the command-line." unless (-d '.git');
}

sub get_password {
	my $passfile = File::Spec->catfile($ENV{'HOME'}, '.signingpass');
	if (not -r $passfile) {
		die "Unable to locate $passfile!\n";
	}
	chomp(my $ret = read_file($passfile));
	return $ret;
}

sub get_repository {
	if (not -r '.nightly') {
		die "Unable to locate .nightly file in the current directory!\n";
	}
	chomp(my $ret = read_file('.nightly'));
	return $ret;
}

sub usage {
	my $error = shift;

	print <<END;
usage: $0 [-h] -t <type>

	-h            : print this help
	-t <type>     : type of build: rpm, debian, installer

END

	if (defined $error) {
		print "ERROR: $error\n\n";
	}

	exit(1);
}
