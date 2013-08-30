#!/usr/bin/perl -w

use strict;
use warnings;

$|++;

use Cwd qw(abs_path);
use File::Basename;
use File::Find;
use File::Path;
use File::Slurp;
use File::Spec;
use Getopt::Long;
use Git;
use IO::Handle;

use OpenNMS::Release 2.9.4;

use vars qw(
	$SCRIPTDIR
	$ROOTDIR
	$SOURCEDIR
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

print $0, " version ", $OpenNMS::Release::VERSION, "\n";

$SCRIPTDIR     = abs_path(dirname($0));
$ROOTDIR       = abs_path('.');
$SOURCEDIR     = abs_path('.');
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
	"r|rootdir=s"     => \$ROOTDIR,
	"s|sourcedir=s"   => \$SOURCEDIR,
) or die "Unable to parse command-line: $@\n";

usage() if ($HELP);

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
Build Root:    $ROOTDIR
Source Root:   $SOURCEDIR

Type:          $TYPE
Source Branch: $BRANCH
Timestamp:     $TIMESTAMP
Revision:      $MICRO_REVISION
Repository:    $REPOSITORY

END

print "- cleaning up git and \$M2_REPO:\n";
clean_for_build();

if ($TYPE eq 'rpm') {
	make_rpm();
} elsif ($TYPE eq 'debian') {
	make_debian();
} elsif ($TYPE eq 'installer') {
	make_installer();
} else {
	usage("unknown build type: $TYPE");
}

buildtool('save');

sub make_rpm {
	my @command = (
		File::Spec->catfile($SOURCEDIR, 'makerpm.sh'),
		'-s', $PASSWORD,
		'-m', $TIMESTAMP,
		'-u', $MICRO_REVISION,
	);

	if ($ASSEMBLY_ONLY) {
		push(@command, '-a');
	}

	system(@command) == 0 or die "Failed to run makerpm.sh: $!\n";
}

sub make_debian {
	my @command = (
		File::Spec->catfile($SOURCEDIR, 'makedeb.sh'),
		'-s', $PASSWORD,
		'-m', $TIMESTAMP,
		'-u', $MICRO_REVISION,
	);

	if ($ASSEMBLY_ONLY) {
		push(@command, '-a');
	}

	system(@command) == 0 or die "Failed to run makedeb.sh: $!\n";
}

sub make_installer {
	my @command = (
		File::Spec->catfile($ROOTDIR, 'make-installer.sh'),
		'-m', $TIMESTAMP,
		'-u', $MICRO_REVISION,
	);

	if ($ASSEMBLY_ONLY) {
		push(@command, '-a');
	}

	system(@command) == 0 or die "Failed to run make-installer.sh: $!\n";
}

sub buildtool {
	my $command = shift;

	my $handle = IO::Handle->new();

	open($handle, '-|', "$CMD_BUILDTOOL 'snapshot-$TYPE' '$command' '$BRANCH' '$SOURCEDIR'") or die "Unable to run $CMD_BUILDTOOL 'snapshot-$TYPE' '$command' '$BRANCH' '$SOURCEDIR': $!\n";
	chomp(my $output = read_file($handle));
	close($handle) or die "Failed to close $CMD_BUILDTOOL call: $!\n";

	return $output;
}

sub clean_up_jars {
	my $name = $File::Find::name;
	return unless (-f $name and $name =~ /\.jar$/);

	chomp(my $type = `file '$name'`);
	if ($type !~ /zip archive/i) {
		unlink($name);
		return;
	}

	if (-M $name > 7 or -C $name > 7) {
		unlink($name);
		return;
	}
}

sub clean_for_build {
	if (-d '.git') {
		my $git = Git->repository( Directory => $SOURCEDIR );
		$git->command('clean', '-fdx');
		$git->command('reset', '--hard', 'HEAD');
	}

	my $maven_dir = File::Spec->catdir($ENV{'HOME'}, '.m2', 'repository');
	find(\&clean_up_jars, $maven_dir);

	my $opennms_dir = File::Spec->catdir($maven_dir, 'org', 'opennms');
	rmtree($opennms_dir) unless (not -d $opennms_dir);
}

sub get_branch {
	my $gitdir     = File::Spec->catdir($SOURCEDIR, '.git');
	my $branchfile = File::Spec->catfile($SOURCEDIR, 'opennms-build-branch.txt');

	if (-d $gitdir) {
		my $git = Git->repository( Directory => $SOURCEDIR );
		try {
			my $ref = $git->command_oneline('symbolic-ref', 'HEAD');
			if (defined $ref and $ref =~ /refs/) {
				my ($ret) = $ref =~ /.*\/([^\/]*)$/;
				return $ret;
			}
		} catch {
		}
		die "Found a .git directory in $SOURCEDIR, but we were unable to determine the branch name!\n";
	} elsif (-r $branchfile) {
		chomp(my $branch_name = read_file($branchfile));
		return $branch_name;
	}

	die "No valid .git directory found, and opennms-build-branch.txt does not exist!  Please specify a branch name on the command-line.";
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
	my $nightlyfile = File::Spec->catfile($SOURCEDIR, '.nightly');
	my $buildrepofile = File::Spec->catfile($ROOTDIR, 'opennms-build-repo.txt');

	my $ret = undef;

	FILELOOP: for my $file ($nightlyfile, $buildrepofile) {
		next FILELOOP unless (-r $file);

		my $handle = IO::Handle->new();
		open($handle, '<', $file) or die "Failed to read from $file: $!\n";
		while (my $line = <$handle>) {
			chomp($line);
			if ($line =~ /^repo:\s*(.*?)\s*$/) {
				$ret = $1;
				last FILELOOP;
			}
		}
		close($handle) or die "Failed to close $file filehandle: $!\n";
	}

	if (not defined $ret) {
		die "Unable to determine repository from nightly files!\n";
	}

	return $ret;
}

sub usage {
	my $error = shift;

	print <<END;
usage: $0 [-h] -t <type> [-b <branch_name>] [-a] [-r <rootdir>] [-s <sourcedir>]

	-h               : print this help
	-t <type>        : type of build: rpm, debian, installer
	-b <branch_name> : specify the branch name, rather than detecting it
	-a               : do an assembly-only build
	-r <rootdir>     : the root directory where building should take place
	-s <sourcedir>   : the location of the OpenNMS source, if not rootdir

END

	if (defined $error) {
		print "ERROR: $error\n\n";
	}

	exit(1);
}
