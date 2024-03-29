#!/usr/bin/perl -w

use 5.026;

use strict;
use warnings;

use Getopt::Long qw(:config gnu_getopt);

use Cwd qw(abs_path);
use Data::Dumper;
use Fcntl qw(LOCK_EX LOCK_NB);
use File::Basename;
use File::Copy;
use File::Find;
use File::NFSLock qw(uncache);
use File::Path qw(mkpath remove_tree);
use File::Temp qw(tempdir tempfile);

use version;

use vars qw(
	$HELP
	$DEBUG
	$SKIP_INDEX

	$BOOTSTRAPVERSION
	$DESCRIPTIONS

	$ROOT
	$PROJECTROOT
	$BRANCH

	$DOCS
	@PROJECTS
	$PROJECT
	$PROJECTNAME
	$VERSION

	$BRANCHDIR
	$DOCDIR
	$INSTALLDIR
);

$DEBUG = 0;
$SKIP_INDEX = 0;
$ROOT = '/opt/mecha/docs.opennms.org';

$BOOTSTRAPVERSION = '3.3.4';
$DESCRIPTIONS = {
	'branches'          => 'Development',
	'documentation'     => 'Documentation',
	'guide-admin'       => 'Admin',
	'guide-development' => 'Developers',
	'guide-concepts'    => 'Concepts',
	'guide-doc'         => 'Documentation',
	'guide-install'     => 'Installation',
	'guide-user'        => 'Users',
	'helm'              => 'Helm',
	'javadoc'           => 'Java API',
	'jicmp'             => 'JICMP',
	'jicmp6'            => 'JICMP6',
	'jmx',              => 'JMX',
	'jrrd'              => 'JRRD',
	'jrrd2'             => 'JRRD2',
	'minion'            => 'Minion',
	'opennms'           => 'OpenNMS',
	'opennms-js'        => 'OpenNMS.js',
	'pris'              => 'PRIS',
	'rancid-api'        => 'RANCID',
	'releasenotes'      => 'Release Notes',
	'releases'          => 'Releases',
	'sampler'           => 'Sampler',
	'xsds',             => 'XML Schemas',
};

my $result = GetOptions(
	"h|help"       => \$HELP,
	"d|debug"      => \$DEBUG,
	"s|skip-index" => \$SKIP_INDEX,

	"r|root=s"     => \$ROOT,
	"b|branch=s"   => \$BRANCH,
);

if (not defined $ROOT or $ROOT eq "") {
	usage();
}

$DOCS    = shift @ARGV;
$PROJECT = shift @ARGV;
$VERSION = shift @ARGV;

if (not defined $DOCS or $DOCS eq "") {
	print STDERR "ERROR: You must specify a document directory/file and a version!\n";
	usage();
}

if (not defined $PROJECT or $PROJECT eq "") {
	print STDERR "ERROR: You must also specify a project!\n";
	usage();
}

if (not defined $VERSION or $VERSION eq "") {
	print STDERR "ERROR: You must also specify a version!\n";
	usage();
}

if ($VERSION =~ /-SNAPSHOT$/ and not defined $BRANCH) {
	print STDERR "ERROR: version is a snapshot but no branch has been specified!\n";
	usage();
}

$DOCS = abs_path($DOCS);
$PROJECT = lc($PROJECT);
$PROJECTROOT = File::Spec->catdir($ROOT, $PROJECT);
$PROJECTNAME = (exists $DESCRIPTIONS->{$PROJECT}? $DESCRIPTIONS->{$PROJECT}:ucfirst($PROJECT));

if (! -d $PROJECTROOT) {
	print STDERR "WARNING: Creating project root: $PROJECTROOT\n";
	mkpath($PROJECTROOT);
}

if (not defined $BRANCH or $BRANCH eq "") {
	$BRANCH = undef;
	$INSTALLDIR = File::Spec->catdir($PROJECTROOT, 'releases', $VERSION);
} else {
	$BRANCHDIR = $BRANCH;
	$BRANCHDIR =~ s/[^[:alnum:]\.\-]+/-/g;
	$INSTALLDIR = File::Spec->catdir($PROJECTROOT, 'branches', $BRANCHDIR);
}

my $lockfile = File::Spec->catfile($ROOT, '.update-doc-repo.lock');
my $LOCK_HANDLE;

### set up a lock - lasts until object loses scope
my $lock;
my $timeout = time() + (60 * 60); # 60 minutes

LOCK: while(time() < $timeout) {
	do_log("- waiting for lock...");

	$lock = new File::NFSLock {
		file      => $lockfile,
		lock_type => LOCK_EX|LOCK_NB,
		blocking_timeout   => $timeout,
		stale_lock_timeout => $timeout * 2,
	};

	# if we get a lock, update the lock file
	if ($lock) {
		open($LOCK_HANDLE, ">", "$lockfile") || die "Failed to lock $ROOT: $!\n";
		print $LOCK_HANDLE localtime(time());
		$lock->uncache;
		do_log("- got lock -- updating documentation");
		last LOCK;
	}

	# otherwise keep waiting
	sleep(5);
}

if (!$lock) {
	die "Couldn't lock $lockfile [$File::NFSLock::errstr]";
}

##### START UPDATING, INSIDE LOCK #####

do_log("- Creating document directory '$INSTALLDIR'");
mkpath($INSTALLDIR);

if (-f $DOCS) {
	$DOCDIR = tempdir( CLEANUP => 1 );
	do_debug("! Created temporary directory $DOCDIR");
	mkpath($DOCDIR);
	do_log("- Unpacking '$DOCS' into temporary directory");
	chdir($DOCDIR);
	if ($DOCS =~ /\.(jar|zip)$/) {
		system('unzip', '-q', $DOCS) == 0 or die "Failed to unpack $DOCS into $DOCDIR: $!\n";
	} elsif ($DOCS =~ /\.tar\.gz$/) {
		system('tar', '-xf', $DOCS) == 0 or die "Failed to unpack $DOCS into $DOCDIR: $!\n";
	} else {
		die "Unhandled file: $DOCS\n";
	}
	chdir($INSTALLDIR);
} else {
	$DOCDIR = $DOCS;
}

if (-d File::Spec->catdir($DOCDIR, 'releasenotes') and -d File::Spec->catdir($DOCDIR, 'guide-admin')) {
	process_opennms_asciidoc_docdir($DOCDIR);
} elsif (-f File::Spec->catfile($DOCDIR, 'xsds', 'event.xsd')) {
	process_basic_docdir(File::Spec->catdir($DOCDIR, 'xsds'), 'xsds');
} elsif (-f File::Spec->catfile($DOCDIR, 'MINION.html')) {
	process_minion_asciidoc_docdir($DOCDIR);
} elsif (-f File::Spec->catfile($DOCDIR, 'introduction.html') and -f File::Spec->catfile($DOCDIR, 'mapper.ocs.html')) {
	process_basic_docdir($DOCDIR, 'pris');
} elsif (-f File::Spec->catdir($DOCDIR, 'docs', 'devguide.html') and -f File::Spec->catfile($DOCDIR, 'docs', 'adminref.html')) {
	process_docbook_docdir(File::Spec->catdir($DOCDIR, 'docs'));
} elsif (-f File::Spec->catdir($DOCDIR, 'devguide.html') and -f File::Spec->catfile($DOCDIR, 'adminref.html')) {
	process_docbook_docdir($DOCDIR);
} elsif (-f File::Spec->catfile($DOCDIR, 'apidocs', 'index-all.html') and -f File::Spec->catfile($DOCDIR, 'apidocs', 'allclasses-frame.html')) {
	process_javadoc_docdir(File::Spec->catdir($DOCDIR, 'apidocs'));
} elsif (-f File::Spec->catfile($DOCDIR, 'index-all.html') and -f File::Spec->catfile($DOCDIR, 'allclasses-frame.html')) {
	process_javadoc_docdir($DOCDIR);
} elsif (-f File::Spec->catfile($DOCDIR, 'index-all.html') and -f File::Spec->catfile($DOCDIR, 'allclasses-index.html')) {
	process_javadoc_docdir($DOCDIR);
} elsif (-f File::Spec->catfile($DOCDIR, 'index.html') and -f File::Spec->catfile($DOCDIR, 'search-index.js') and (-d File::Spec->catfile($DOCDIR, 'horizon') or (-d File::Spec->catfile($DOCDIR, 'meridian')))) {
	process_basic_docdir($DOCDIR, 'documentation');
} elsif (-f File::Spec->catfile($DOCDIR, 'index.html') and -f File::Spec->catfile($DOCDIR, 'globals.html')) {
	process_basic_docdir($DOCDIR, 'opennms-js');
} elsif (-f File::Spec->catfile($DOCDIR, '_', 'js', 'site.js')) {
	process_basic_docdir($DOCDIR, 'helm');
} elsif (-d File::Spec->catfile($DOCDIR, '_package', 'helm')) {
	process_basic_docdir(File::Spec->catfile($DOCDIR, '_package', 'helm'), 'helm');
} else {
	system('ls', '-la', $DOCDIR);
	die "Unknown documentation type: $DOCS\n";
}

my $versionfile = File::Spec->catfile($INSTALLDIR, '.version.txt');
my $VERSION_FILE_HANDLE;
open ($VERSION_FILE_HANDLE, '>', $versionfile) or die "Failed to open $versionfile for writing: $!\n";
print $VERSION_FILE_HANDLE $VERSION;
close($VERSION_FILE_HANDLE) or die "Failed to close $versionfile: $!\n";

if (not $SKIP_INDEX) {
	@PROJECTS = get_projects($ROOT);
	update_indexes();
	create_release_symlinks();
	fix_permissions($INSTALLDIR);
}

END {
	##### FINISHED UPDATING, CLOSE LOCK #####

	if (defined $lockfile and defined $lock) {
		do_log("- cleaning up lock...");
		unlink($lockfile) or die "Failed to remove $lockfile: $!\n";
		close($LOCK_HANDLE) or die "Failed to close $lockfile: $!\n";
		$lock->unlock();
	}
}

exit 0;

sub do_log {
	print localtime(time()) . " " . join('', @_) . "\n";
}

sub do_debug {
	return unless $DEBUG;
	print localtime(time()) . " " . join('', @_) . "\n";
}

sub get_projects {
	my $projectsroot = shift;

	do_debug("! Getting projects from $projectsroot:");
	my $projects = {};
	my $PROJECT_HANDLE;
	opendir($PROJECT_HANDLE, $projectsroot) or die "Failed to open $projectsroot for reading: $!\n";
	while (my $entry = readdir($PROJECT_HANDLE)) {
		next if ($entry =~ /^\./);
		next if ($entry =~ /^\@eaDir/);
		next if ($entry =~ /^index\.html$/);
		next if ($entry =~ /^(api|documentation|Minion-Events|OpenNMS|PRIS|SMNnepO)$/);
		next if ($entry =~ /^opennms-style/);
		my $path = File::Spec->catdir($projectsroot, $entry);
		next if (-l $path);
		next unless (-d $path);

		my $project = {
			name        => $entry,
			description => (exists $DESCRIPTIONS->{$entry}? $DESCRIPTIONS->{$entry}:ucfirst($entry)),
			path        => $path,
		};

		do_debug("! * Found: ", $project->{'description'});
		$projects->{$entry} = $project;
	}
	closedir($PROJECT_HANDLE) or die "Failed to close $projectsroot: $!\n";

	for my $project (sort keys %$projects) {
		my $releases = get_releases($projects->{$project});
		$projects->{$project}->{'releases'} = $releases;
	}

	my @ret;
	for my $project (sort {
		if ($a eq 'opennms') {
			return -1;
		} elsif ($b eq 'opennms') {
			return 1;
		} else {
			return $a cmp $b;
		}
	} keys %$projects) {
		if ($project eq 'opennms') {
			push(@ret, $projects->{$project});
		}
	}
	return @ret;
}

sub get_releases {
	my $project = shift;
	my @releases;

	do_debug("! Getting release types for project " . $project->{'description'});
	my $RELEASES_HANDLE;
	opendir($RELEASES_HANDLE, $project->{'path'}) or die "Failed to open " . $project->{'path'} . " for reading: $!\n";
	for my $entry (sort readdir($RELEASES_HANDLE)) {
		next unless ($entry =~ /^(branches|releases)$/);
		do_debug("! * Found release type: $entry");
		do_debug("! * Searching for releases:");

		my $releasesdir = File::Spec->catdir($project->{'path'}, $entry);
		my $RELEASE_HANDLE;
		opendir($RELEASE_HANDLE, $releasesdir) or die "Failed to open $releasesdir for reading: $!\n";
		for my $releaseentry (sort readdir($RELEASE_HANDLE)) {
			next if ($releaseentry =~ /^\./);
			next if ($releaseentry =~ /^\@eaDir/);
			next if ($releaseentry =~ /^index\.html$/);
			my $releasedir = File::Spec->catdir($releasesdir, $releaseentry);
			next if (-l $releasedir);
			next unless (-d $releasedir);

			do_debug("!   * Found: $releaseentry");

			my $release = {
				type    => $entry,
				name    => $releaseentry,
				path    => $releasedir,
				project => $project,
			};

			my $versionfile = File::Spec->catfile($releasedir, '.version.txt');
			if (-e $versionfile) {
				my $VERSION_HANDLE;
				open($VERSION_HANDLE, '<', $versionfile) or die "Failed to open $versionfile for reading: $!\n";
				my $version = <$VERSION_HANDLE>;
				chomp($version);
				if (defined $version and $version ne "") {
					$release->{'version'} = $version;
				}
				close($VERSION_HANDLE);
			}

			push(@releases, $release);
		}
		closedir($RELEASE_HANDLE) or die "Failed to close $releasesdir: $!\n";
	}
	closedir($RELEASES_HANDLE) or die "Failed to close " . $project->{'path'} . "\n";

	for my $release (@releases) {
		my $docs = get_docs_for_release($release);
		$release->{'docs'} = $docs;
	}

	return \@releases;
}

sub get_docs_for_release {
	my $release = shift;
	my $docs = {};

	my $display = $release->{'type'} . '/' . $release->{'name'};
	do_debug("! Finding documentation in $display...");
	my $DOCS_HANDLE;
	opendir($DOCS_HANDLE, $release->{'path'}) or die "Failed to open " . $release->{'path'} . " for reading: $!\n";
	for my $entry (sort readdir($DOCS_HANDLE)) {
		next if ($entry =~ /^\./);
		next if ($entry =~ /^\@eaDir/);
		next if ($entry =~ /^index\.html$/);
		my $docpath = File::Spec->catdir($release->{'path'}, $entry);
		next if (-l $docpath);
		next unless (-d $docpath);

		do_debug("  $entry...");

		my $doc = {
			name => $entry,
			description => (exists $DESCRIPTIONS->{$entry}? $DESCRIPTIONS->{$entry}:$entry),
			path        => $docpath,
			release     => $release,
		};

		for my $extension ('html', 'pdf') {
			my $path = File::Spec->catfile($docpath, $entry.'.'.$extension);
			$doc->{'types'}->{$extension} = $path if (-e $path);
		}

		if (not $doc->{'types'}) {
			my $target = File::Spec->catfile($docpath, 'index.html');
			if (not -e $target) {
				$target = $docpath;
			}
			$doc->{'types'} = {
				html => $target
			};
		}

		$docs->{$entry} = $doc;
	}
	closedir($DOCS_HANDLE) or die "Failed to close " . $release->{'path'} . ": $!\n";

	return $docs;
}

sub get_releases_for_project {
	my $project = shift;
	my @releases = sort { versioncmp($b->{'name'}, $a->{'name'}) } grep { $_->{'type'} eq 'releases' } @{$project->{'releases'}};
	return @releases;
}

sub get_branches_for_project {
	my $project = shift;

	return qw();
	my @ret = sort { $a->{'name'} cmp $b->{'name'} } grep { $_->{'type'} eq 'branches' and $_->{'name'} =~ /^(develop|foundation|master)$/ } @{$project->{'releases'}};
	push(@ret, sort { $a->{'name'} cmp $b->{'name'} } grep { $_->{'type'} eq 'branches' and $_->{'name'} !~ /^(develop|foundation|master)$/ } @{$project->{'releases'}});
	return @ret;
}

sub update_indexes {
	do_log("- updating indexes...");

	my $ROOT_HANDLE;
	opendir($ROOT_HANDLE, $ROOT) or die "Failed to open $ROOT for reading: $!\n";

	my $roottext = "<h3>OpenNMS Projects</h3>\n<ul>\n";
	for my $project (@PROJECTS) {

		my $desc = $project->{'description'};
		my $projectdir = $project->{'path'};

		do_debug("- updating indexes for " . $desc);

		$roottext .= "	<li class=\"project\">\n";
		$roottext .= get_link($desc, File::Spec->catdir($projectdir, 'index.html'), $ROOT) . "\n";
		$roottext .= "		<ul>\n";

		if ($project->{'releases'}) {
			my @releases = get_releases_for_project($project);
			my @branches = get_branches_for_project($project);

			if (@releases > 0) {
				my $release = $releases[0];
				$roottext .= "			<li>Releases: [";
				$roottext .= get_link($release->{'name'}, File::Spec->catdir($release->{'path'}, 'index.html'), $ROOT) . ", ";
				$roottext .= get_link('Browse', File::Spec->catdir($project->{'path'}, 'releases', 'index.html'), $ROOT);
				$roottext .= "]</li>\n";
			}
			if (@branches > 0) {
				$roottext .= "			<li>Development: [";
				my $latest_release = get_latest_development_release(@branches);
				if ($latest_release) {
					my $linkname = 'Latest';
					if ($latest_release->{'version'}) {
						$linkname = $latest_release->{'version'};
					}
					$roottext .= get_link($linkname . ' (' . $latest_release->{'name'} . ')', File::Spec->catdir($latest_release->{'path'}, 'index.html'), $ROOT) . ", ";
				}
				$roottext .= get_link('Browse', File::Spec->catdir($project->{'path'}, 'branches', 'index.html'), $ROOT);
				$roottext .= "]</li>\n";
			}
		}

		$roottext .= "		</ul>\n";
		$roottext .= "	</li>\n";

		update_project_indexes($project);
	}
	$roottext .= "</ul>\n";
	write_html('OpenNMS Projects', $roottext, File::Spec->catfile($ROOT, 'index.html'));
}

sub create_release_symlinks {
	for my $project (@PROJECTS) {
		my @releases = get_releases_for_project($project);
		my $release = shift @releases;
		if (defined $release) {
			my $releasedir = File::Spec->catdir($project->{'path'}, 'releases');
			my $latestfile = File::Spec->catfile($releasedir, 'latest');
			if (-e $latestfile) {
				unlink $latestfile;
			}
			do_debug('! ln -sf ' . $release->{'name'} . ' ' . $latestfile);
			symlink($release->{'name'}, $latestfile);
		}
	}
}

sub get_latest_development_release {
	my @releases = @_;

	my $develop = get_release('develop', @releases);
	if ($develop) {
		return $develop;
	}

	my $master = get_release('master', @releases);
	return $master;
}

sub get_release {
	my $name = shift;
	my @matching = grep { $_->{'name'} eq $name } @_;
	if (@matching > 0) {
		return $matching[0];
	}
	return;
}

sub update_project_indexes {
	my $project  = shift;

	my @releases = get_releases_for_project($project);
	my @branches = get_branches_for_project($project);

	my $projecttext = "";

	if (@releases > 0) {
		my $title = $project->{'description'} . ' Releases';
		my $releasedir = File::Spec->catdir($project->{'path'}, 'releases');

		$projecttext .= "<h3>$title</h3>\n<ul>\n";
		my $releasetext = "<h3>$title</h3>\n<ul>\n";

		for my $release (@releases) {
			$projecttext .= "<li>" . get_release_link($release, $project->{'path'}) . "</li>\n";
			$releasetext .= "<li>" . get_release_link($release, $releasedir) . "</li>\n";
			update_release_indexes($release);
		}

		$projecttext .= "</ul>\n";
		$releasetext .= "</ul>\n";

		write_html($title, $releasetext, File::Spec->catfile($project->{'path'}, 'releases', 'index.html'));
	}

	if (@branches > 0) {
		my $title = $project->{'description'} . ' Development';
		my $branchdir = File::Spec->catdir($project->{'path'}, 'branches');

		$projecttext .= "<h3>$title</h3>\n<ul>\n";
		my $branchtext = "<h3>$title</h3>\n<ul>\n";

		for my $branch (@branches) {
			$projecttext .= "<li>" . get_release_link($branch, $project->{'path'}) . "</li>\n";
			$branchtext .= "<li>" . get_release_link($branch, $branchdir) . "</li>\n";
			update_release_indexes($branch);
		}

		$projecttext .= "</ul>\n";
		$branchtext .= "</ul>\n";

		write_html($title, $branchtext, File::Spec->catfile($project->{'path'}, 'branches', 'index.html'));
	}

	write_html($project->{'description'} . ' Documentation', $projecttext, File::Spec->catfile($project->{'path'}, 'index.html'));
}

sub update_release_indexes {
	my $release  = shift;

	my $title = $release->{'project'}->{'description'} . ' ' . $DESCRIPTIONS->{$release->{'type'}} . ": " . $release->{'name'};
	if ($release->{'version'} and $release->{'version'} ne $release->{'name'}) {
		$title .= ' (' . $release->{'version'} . ')';
	}
	my $releasetext = "<h3>$title</h3>\n";
	$releasetext .= "<ul>\n";
	for my $doc (get_docobjs($release)) {
		$releasetext .= "<li>" . $doc->{'description'} . " (";
		for my $type ('html', 'pdf') {
			if ($doc->{'types'}->{$type}) {
				$releasetext .= get_link($type, $doc->{'types'}->{$type}, $release->{'path'}) . ", ";
			}
		}
		$releasetext =~ s/, $//;
		$releasetext .= ")</li>\n";
	}
	$releasetext .= "</ul>\n";

	write_html($title, $releasetext, File::Spec->catfile($release->{'path'}, 'index.html'));
}

sub get_docobjs {
	my $release = shift;

	my @docs;
	for my $key (sort {
		if ($a eq 'releasenotes') { return -1; }
		if ($b eq 'releasenotes') { return 1; }
		if ($a eq 'javadoc') { return 1; }
		if ($b eq 'javadoc') { return -1; }
		return $a cmp $b;
	} keys %{$release->{'docs'}}) {
		push(@docs, $release->{'docs'}->{$key});
	}

	return @docs;
}

sub get_release_link {
	my $release     = shift;
	my $relative_to = shift;

	my $linktext = get_link($release->{'name'}, File::Spec->catfile($release->{'path'}, 'index.html'), $relative_to) . ': ';
	if ($release->{'version'} and $release->{'version'} ne $release->{'name'}) {
		$linktext .= $release->{'version'} . ' ';
	}
	$linktext .= '<span class="release">';

	for my $doc (get_docobjs($release)) {
		$linktext .= get_link($doc->{'description'}, $doc->{'types'}->{'html'}, $relative_to);
		if ($doc->{'types'}->{'pdf'}) {
			$linktext .= ' (' . get_link('pdf', $doc->{'types'}->{'pdf'}, $relative_to) . ')';
		}
		$linktext .= ', ';
	}

	$linktext =~ s/, $//;
	$linktext .= "</span>";
	return $linktext;
}


sub get_link {
	my $description = shift;
	my $file        = shift;
	my $relative_to = shift;

	return "<a href=\"" . File::Spec->abs2rel($file, $relative_to) . "\">$description</a>";
}

sub write_html {
	my $title    = shift;
	my $text     = shift;
	my $file     = shift;

	my $dirname = dirname($file);
	my $relative_topdir = File::Spec->abs2rel($ROOT, $dirname);
	my $relative_top    = File::Spec->catdir($relative_topdir, 'index.html');

	my $top_relative = File::Spec->abs2rel($dirname, $ROOT);
	my @dirs = File::Spec->splitdir($top_relative);
	my $current_project = shift @dirs;

	my $FILEOUT_HANDLE;

	open($FILEOUT_HANDLE, '+>', $file .'.new') or die "Failed to open $file for writing: $!\n";
	print $FILEOUT_HANDLE <<END;
<!DOCTYPE html>
<html lang="en">
	<head>
		<meta charset="utf-8">
		<meta http-equiv="X-UA-Compatible" content="IE=edge">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<title>$title</title>
		<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/${BOOTSTRAPVERSION}/css/bootstrap.min.css">
		<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/${BOOTSTRAPVERSION}/css/bootstrap-theme.min.css">
		<style type="text/css">
			  body {
				  padding-top: 50px;
				  background-color: #0A0C1B; /* chromatic black */
				  background-image: url('/opennms-style/art-assets/background-dark.png');
				  background-size: cover;
				  color: #E9EBF9; /* cool gray 1 */
			  }
			  h3 {
				  color: #14D1DF; /* sky blue */
			  }
			  a, a:link, a:hover, a:active {
				  color: #E9EBF9; /* cool gray 1 */
			  }
			  a:visited {
				  color: #B4B6C8; /* cool gray 2 */
			  }
			  li.project {
				  list-style: none;
			  }
			  .release::before {
				  content: "  ";
				  white-space: pre;
			  }
			  .navbar-brand img {
				  height: 30px;
				  width: 30px;
				  margin-top: -5px;
			  }
			  .navbar-inverse {
				  color: #14D1DF; /* sky blue */
				  background-color: #0A0C1B; /* chromatic black */
				  background-image: none;
			  }
			  .navbar-inverse .navbar-brand {
				  color: #14D1DF; /* sky blue */
			  }
			  .navbar-inverse .navbar-nav > li > a {
				  color: #14D1DF; /* sky blue */
			  }
			  .dropdown-menu {
				  background-color: #E9EBF9; /* cool gray 1 */
			  }
			  .dropdown-menu > li > a {
				  color: #0A0C1B; /* chromatic black */
			  }
		</style>
	</head>
	<body>
		<nav class="navbar navbar-inverse navbar-fixed-top">
			<div class="container">
				<div class="navbar-header">
					<button type="button" class="navbar-toggle collapsed" data-toggle="collapse" data-target="#navbar">
						<span class="sr-only">Toggle navigation</span>
						<span class="icon-bar"></span>
						<span class="icon-bar"></span>
						<span class="icon-bar"></span>
					</button>
					<a class="navbar-brand" href="index.html">
						<img src="/opennms-style/art-assets/OpenNMS_Logo-Mark_Full-color.svg" alt="OpenNMS Documentation" />
					</a>
				</div>
				<div id="navbar" class="collapse navbar-collapse">
					<ul class="nav navbar-nav">
END

	for my $project (@PROJECTS) {
		if ($project->{'name'} eq $current_project) {
			print $FILEOUT_HANDLE "<li class=\"dropdown active\">";
		} else {
			print $FILEOUT_HANDLE "<li class=\"dropdown\">";
		}
		print $FILEOUT_HANDLE "<a href=\"#\" class=\"dropdown-toggle\" data-toggle=\"dropdown\" role=\"button\" aria-expanded=\"false\">" . $project->{'description'} . " <span class=\"caret\"></span></a>\n";
		print $FILEOUT_HANDLE "<ul class=\"dropdown-menu\" role=\"menu\">\n";

		my @releases = get_releases_for_project($project);
		my @branches = get_branches_for_project($project);

		my $count = 0;
		if (@releases > 0) {
			my $active = "";
			my $releaseslink = File::Spec->catfile($project->{'path'}, 'releases', 'index.html');
			if ($releaseslink eq $file) {
				$active = " class=\"active\"";
			}

			print $FILEOUT_HANDLE "<li$active>" . get_link("<strong>Releases</strong>", $releaseslink, $dirname) . "</li>\n";
			#print $FILEOUT_HANDLE "<li class=\"divider\"></li>\n";
			for my $release (@releases) {
				my $releaselink = File::Spec->catfile($release->{'path'}, 'index.html');
				$active = "";
				if ($releaselink eq $file) {
					$active = " class=\"active\"";
				}
				print $FILEOUT_HANDLE "<li${active}>" . get_link($release->{'name'}, $releaselink, $dirname) . "</li>\n";
				last if (++$count == 5);
			}
			if (@releases > 5) {
				print $FILEOUT_HANDLE "<li>" . get_link("more...", $releaseslink, $dirname) . "</li>\n";
			}
			if (@branches > 0) {
				print $FILEOUT_HANDLE "<li class=\"divider\"></li>\n";
			}
		}

		if (@branches > 0) {
			my $active = "";
			my $brancheslink = File::Spec->catfile($project->{'path'}, 'branches', 'index.html');
			if ($brancheslink eq $file) {
				$active = " class=\"active\"";
			}

			print $FILEOUT_HANDLE "<li$active>" . get_link("<strong>Branches</strong>", $brancheslink, $dirname) . "</li>\n";
			#print $FILEOUT_HANDLE "<li class=\"divider\"></li>\n";
			for my $branch (@branches) {
				if ($branch->{'name'} !~ /^(develop|foundation|master)$/) {
					print $FILEOUT_HANDLE "<li>" . get_link("more...", $brancheslink, $dirname) . "</li>\n";
					last;
				}

				my $branchlink = File::Spec->catfile($branch->{'path'}, 'index.html');
				$active = "";
				if ($branchlink eq $file) {
					$active = " class=\"active\"";
				}
				print $FILEOUT_HANDLE "<li${active}>" . get_link($branch->{'name'}, $branchlink, $dirname) . "</li>\n";
			}
		}

		print $FILEOUT_HANDLE "</ul>\n";
		print $FILEOUT_HANDLE "</li>\n";
	}

	print $FILEOUT_HANDLE <<END;
					</ul>
				</div>
			</div>
		</nav>

		<div class="container">
END

	print $FILEOUT_HANDLE $text;
	print $FILEOUT_HANDLE <<END;
		</div>
		<script src="https://code.jquery.com/jquery-2.1.4.min.js"></script>
		<script src="https://maxcdn.bootstrapcdn.com/bootstrap/${BOOTSTRAPVERSION}/js/bootstrap.min.js"></script>
		<script>
			(function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
			(i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
			m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
			})(window,document,'script','https://www.google-analytics.com/analytics.js','ga');
			ga('create', 'UA-2133604-19', 'auto');
			ga('send', 'pageview');
		</script>
	</body>
</html>
END
	close($FILEOUT_HANDLE) or die "Failed to close ${file}.new: $!\n";
	chmod(0644, "${file}.new") or die "Failed to change ownership of ${file}.new: $!\n";

	if (-e $file) {
		unlink($file) or die "Failed to unlink $file: $!\n";
	}
	link($file . '.new', $file) or die "Failed to link $file.new to $file: $!\n";
	unlink($file . '.new') or die "Failed to remove $file.new: $!\n";
}

sub process_basic_docdir {
	my $docdir = shift;
	my $project = shift;
	copy_doc_directory($docdir, $project);
}

sub process_opennms_asciidoc_docdir {
	my $docdir = shift;

	my $DOCDIR_HANDLE;
	opendir($DOCDIR_HANDLE, $docdir) or die "Failed to open $docdir for reading: $!\n";
	my @guides = sort grep { !/^(\.\.?|\@eaDir)$/ } readdir($DOCDIR_HANDLE);
	closedir($DOCDIR_HANDLE) or die "Failed to close $docdir: $!\n";

	for my $dir (@guides) {
		copy_doc_directory(File::Spec->catdir($docdir, $dir), $dir);
	}
}

sub process_minion_asciidoc_docdir {
	my $docdir = shift;

	my $images = File::Spec->catdir($docdir, 'images');
	my $files  = File::Spec->catdir($docdir, 'files');

	if (-d $images) {
		my $imagedir = File::Spec->catdir($INSTALLDIR, '.images');
		mkpath($imagedir);
		system('rsync', '-rl', '--no-compress', '--delete', $images.'/', $imagedir.'/') == 0 or die "Failed to sync $images to $imagedir: $!\n";
	}

	if (-d $files) {
		my $filedir = File::Spec->catdir($INSTALLDIR, '.files');
		mkpath($filedir);
		system('rsync', '-rl', '--no-compress', '--delete', $files.'/', $filedir.'/') == 0 or die "Failed to sync $files to $filedir: $!\n";
	}

	my $DOCDIR_HANDLE;
	opendir($DOCDIR_HANDLE, $docdir) or die "Failed to open $docdir for reading: $!\n";
	for my $entry (sort { lc($a) cmp lc($b) } grep { /\.html$/ } readdir($DOCDIR_HANDLE)) {
		my ($name) = $entry =~ /^(.*?)\.html$/;
		$name = lc($name);

		my $target = File::Spec->catdir($INSTALLDIR, $name);
		mkpath($target);

		symlink('../.images', File::Spec->catdir($target, 'images')) if (-d $images);
		symlink('../.files', File::Spec->catdir($target, 'files')) if (-d $files);

		my $fromfile = File::Spec->catfile($docdir, $entry);
		my $tofile   = File::Spec->catfile($target, 'index.html');
		copy($fromfile, $tofile) or die "Failed to copy $fromfile to $tofile: $!\n";

		symlink('index.html', File::Spec->catfile($target, $name.'.html'));
	}
	closedir($DOCDIR_HANDLE);
}

sub copy_doc_directory {
	my $from  = shift;
	my $guide = shift;

	my $to = File::Spec->catdir($INSTALLDIR, $guide);

	do_log("- Copying $guide to '$to'");
	find({
		wanted => sub {
			return unless (-f $File::Find::name);
			my $rel = File::Spec->abs2rel($_, $from);
			return if ($rel =~ /\.(adoc|graphml)$/);
			return if ($rel =~ /^images_src\//);

			my $fromfile = File::Spec->catfile($from, $rel);
			my $tofile = File::Spec->catfile($to, $rel);

			my $dirname = dirname($tofile);
			if (not -d $dirname) {
				mkpath($dirname);
				#system('chmod', '755', $dirname) == 0 or die "Failed to fix ownership on $dirname: $!\n";
			}

			do_debug("  - copy: $fromfile -> $tofile");
			copy($fromfile, $tofile) or die "Failed to copy '$fromfile' to '$tofile': $!\n";
			#system('chmod', '644', $tofile) == 0 or die "Failed to fix ownership on $tofile: $!\n";

			if ($rel =~ /^index.(html|pdf)$/) {
				symlink('index.' . $1, File::Spec->catfile($to, $guide . '.' . $1)), "\n";
			}
		},
		bydepth => 1,
		follow => 1,
		no_chdir => 1,
	}, $from);
}

sub process_docbook_docdir {
	my $docdir = shift;

	my $mapping = {
		'adminref'     => 'guide-admin',
		'devguide'     => 'guide-development',
		'install'      => 'guide-install',
		'userguide'    => 'guide-user',
		'releasenotes' => 'releasenotes',
	};

	my $from = File::Spec->catdir($docdir);

	my $DIR_HANDLE;

	opendir($DIR_HANDLE, $from) or die "Failed to open $from for reading: $!\n";
	my @files = sort grep { /\.(pdf|html)$/ } readdir($DIR_HANDLE);
	closedir($DIR_HANDLE) or die "Failed to close $from: $!\n";

	my $common = File::Spec->catdir($from, 'common');
	if (-d $common) {
		my $tocommon = File::Spec->catdir($INSTALLDIR, '.common');
		mkpath($tocommon);

		find({
			wanted => sub {
				return unless (-f $File::Find::name);
				my $rel = File::Spec->abs2rel($_, $common);

				my $fromfile = File::Spec->catfile($common, $rel);
				my $tofile = File::Spec->catfile($tocommon, $rel);

				my $dirname = dirname($tofile);
				if (not -d $dirname) {
					mkpath($dirname);
					#system('chmod', '755', $dirname) == 0 or die "Failed to fix ownership on $dirname: $!\n";
				}

				do_debug("  - copy: $fromfile -> $tofile");
				copy($fromfile, $tofile) or die "Failed to copy '$fromfile' to '$tofile': $!\n";
				#system('chmod', '644', $tofile) == 0 or die "Failed to fix ownership on $tofile: $!\n";
			},
			bydepth => 1,
			follow => 1,
			no_chdir => 1,
		}, $common);
	} else {
		$common = undef;
	}

	my $done = {};

	for my $file (@files) {
		my ($name) = $file =~ /^(.*?)\.(pdf|html)$/;
		next if ($done->{$name});

		do_debug("- Processing $name");

		my $mappedname = (exists $mapping->{$name}? $mapping->{$name} : $name);
		my $to = File::Spec->catdir($INSTALLDIR, $mappedname);

		for my $extension ('pdf', 'html') {
			my $fromfile = File::Spec->catfile($from, $name . '.' . $extension);
			my $tofile   = File::Spec->catfile($to, 'index.' . $extension);

			next unless (-e $fromfile);

			my $dirname  = dirname($tofile);
			if (not -d $dirname) {
				mkpath($dirname);
				#system('chmod', '755', $dirname) == 0 or die "Failed to fix ownership on $dirname: $!\n";
			}

			do_debug("  - copy: $fromfile -> $tofile");
			copy($fromfile, $tofile) or die "Failed to copy '$fromfile' to '$tofile': $!\n";
			#system('chmod', '644', $tofile) or die "Failed to fix ownership on $tofile: $!\n";

			symlink('index.' . $extension, File::Spec->catfile($to, $mappedname . '.' . $extension));

			if (defined $common) {
				symlink('../.common', File::Spec->catfile($to, 'common'));
			}
		}

		$done->{$name}++;
	}
}

sub process_javadoc_docdir {
	my $from = File::Spec->catdir(shift);
	my $to   = File::Spec->catdir($INSTALLDIR, 'javadoc');
	mkpath($to) unless (-d $to);

	do_log("- Copying javadoc to '$to'");
	system('rsync', '-rl', '--no-compress', '--delete', $from.'/', $to.'/') == 0 or die "Failed to sync from $from to $to: $!\n";
	print "done\n";
}

sub fix_permissions {
	my $dir = shift;
	#system('chown', '-R', 'opennms:opennms', $dir) == 0 or die "Failed to fix ownership on $dir: $!\n";
	#system('chmod', '-R', 'a+r', $dir) == 0 or die "Failed to fix permissions on $dir: $!\n";
}

sub usage {
	print STDERR <<END;
usage: $0 [--debug] [--skip-index] [--root=/path/to/doc/root] [--branch=branch_name] <docs> <project> <version>

OPTIONS:

	--debug         enable debug logging
        --skip-index    skip indexing, just copy the files

	--root=/path    the base path for documentation
	--branch=name   the branch name for documentation

END

	exit 1;
}

# from Sort::Versions 1.5
sub versioncmp {
	my @A = ($_[0] =~ /([-.]|\d+|[^-.\d]+)/g);
	my @B = ($_[1] =~ /([-.]|\d+|[^-.\d]+)/g);

	my ($A, $B);
	while (@A and @B) {
		$A = shift @A;
		$B = shift @B;
		if ($A eq '-' and $B eq '-') {
			next;
		} elsif ( $A eq '-' ) {
			return -1;
		} elsif ( $B eq '-') {
			return 1;
		} elsif ($A eq '.' and $B eq '.') {
			next;
		} elsif ( $A eq '.' ) {
			return -1;
		} elsif ( $B eq '.' ) {
			return 1;
		} elsif ($A =~ /^\d+$/ and $B =~ /^\d+$/) {
			if ($A =~ /^0/ || $B =~ /^0/) {
				return $A cmp $B if $A cmp $B;
			} else {
				return $A <=> $B if $A <=> $B;
			}
		} else {
			$A = uc $A;
			$B = uc $B;
			return $A cmp $B if $A cmp $B;
		}
	}
	@A <=> @B;
}

