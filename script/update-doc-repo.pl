#!/usr/bin/perl -w

$|++;

use strict;
use warnings;

use Getopt::Long qw(:config gnu_getopt);

use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Find;
use File::Path qw(mkpath remove_tree);
use File::Temp qw(tempdir tempfile);

use version;

use vars qw(
	$HELP
	$DEBUG

	$BOOTSTRAPVERSION
	$DESCRIPTIONS

	$ROOT
	$PROJECTROOT
	$BRANCH

	$DOCS
	$PROJECT
	$VERSION

	$BRANCHDIR
	$DOCDIR
	$INSTALLDIR
);

$DEBUG = 0;
$ROOT = '/var/www/sites/opennms.org/site/doc';

$BOOTSTRAPVERSION = '3.3.4';
$DESCRIPTIONS = {
	'guide-admin'       => 'Administrators Guide',
	'guide-development' => 'Developers Guide',
	'guide-doc'         => 'Documentation Guide',
	'guide-install'     => 'Installation Guide',
	'guide-user'        => 'Users Guide',
	'releasenotes'      => 'Release Notes',
	'javadoc'           => 'Java API Documentation',
	'opennms'           => 'OpenNMS Horizon',
};

my $result = GetOptions(
	"h|help"     => \$HELP,
	"d|debug"    => \$DEBUG,

	"r|root=s"   => \$ROOT,
	"b|branch=s" => \$BRANCH,
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
	print STDERR "ERROR: Youst must also specify a project!\n";
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

$PROJECT = lc($PROJECT);
$PROJECTROOT = File::Spec->catdir($ROOT, $PROJECT);

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

print "- Creating document directory '$INSTALLDIR'... ";
mkpath($INSTALLDIR);
print "done\n";

if (-f $DOCS) {
	$DOCDIR = tempdir( CLEANUP => 1 );
	print STDERR "! Created temporary directory $DOCDIR.\n" if ($DEBUG);
	mkpath($DOCDIR);
	print "- Unpacking '$DOCS' into temporary directory... ";
	chdir($DOCDIR);
	if ($DOCS =~ /\.zip$/) {
		system('unzip', $DOCS) == 0 or die "Failed to unpack $DOCS into $DOCDIR: $!\n";
	} elsif ($DOCS =~ /\.tar\.gz$/) {
		system('tar', '-xf', $DOCS) == 0 or die "Failed to unpack $DOCS into $DOCDIR: $!\n";
	} else {
		die "Unhandled file: $DOCS\n";
	}
	print "done\n";
} else {
	$DOCDIR = $DOCS;
}

if (-d File::Spec->catdir($DOCDIR, 'releasenotes') and -d File::Spec->catdir($DOCDIR, 'guide-admin')) {
	process_asciidoc_docdir($DOCDIR);
} elsif (-d File::Spec->catdir($DOCDIR, 'docs', 'common') and -f File::Spec->catfile($DOCDIR, 'docs', 'adminref.html')) {
	process_docbook_docdir(File::Spec->catdir($DOCDIR, 'docs'));
} elsif (-d File::Spec->catdir($DOCDIR, 'common') and -f File::Spec->catfile($DOCDIR, 'adminref.html')) {
	process_docbook_docdir($DOCDIR);
} elsif (-f File::Spec->catfile($DOCDIR, 'apidocs', 'index-all.html') and -f File::Spec->catfile($DOCDIR, 'apidocs', 'allclasses-frame.html')) {
	process_javadoc_docdir(File::Spec->catdir($DOCDIR, 'apidocs'));
} elsif (-f File::Spec->catfile($DOCDIR, 'index-all.html') and -f File::Spec->catfile($DOCDIR, 'allclasses-frame.html')) {
	process_javadoc_docdir($DOCDIR);
} else {
	die "Unknown documentation type: $DOCS\n";
}

update_indexes();
fix_permissions($INSTALLDIR);

exit 0;

sub update_indexes {
	my $roottext = "<h3>OpenNMS Projects</h3>\n<ul>\n";
	opendir(DIR, $ROOT) or die "Failed to open $ROOT for reading: $!\n";
	my @projects = sort {
		if ($a eq 'opennms') {
			return -1;
		} elsif ($b eq 'opennms') {
			return 1;
		} else {
			return $a cmp $b;
		}
	} grep { !/^\./ && -d File::Spec->catdir($ROOT, $_) } readdir(DIR);
	for my $project (@projects) {
		my $desc = (exists $DESCRIPTIONS->{$project}? $DESCRIPTIONS->{$project} : ucfirst($project));
		$roottext .= '	<li>' . get_link($desc, File::Spec->catfile($ROOT, $project, 'index.html'), $ROOT) . "</li>\n";
	}
	$roottext .= "</ul>\n";
	write_html('OpenNMS Projects', $roottext, File::Spec->catfile($ROOT, 'index.html'));

	my $projecttext = "";
	if (-d File::Spec->catdir($PROJECTROOT, 'releases')) {
		$projecttext .= process_tree(File::Spec->catdir($PROJECTROOT, 'releases'));
	}

	if (-d File::Spec->catdir($PROJECTROOT, 'branches')) {
		$projecttext .= process_tree(File::Spec->catdir($PROJECTROOT, 'branches'));
	}

	my $project = (exists $DESCRIPTIONS->{$PROJECT}? $DESCRIPTIONS->{$PROJECT} : ucfirst($PROJECT));
	write_html($project . ' Documentation', $projecttext, File::Spec->catfile($PROJECTROOT, 'index.html'));
}

sub get_link {
	my $description = shift;
	my $file        = shift;
	my $relative_to = shift;

	return "<a href=\"" . File::Spec->abs2rel($file, $relative_to) . "\">$description</a>";
}

# $ROOT / $PROJECTROOT / tree / release / doc
sub process_tree {
	my $treedir = shift;
	my $treebase = basename($treedir);

	my $headertype = 'OpenNMS ' . ucfirst(lc($treebase));

	# relative to the $treedir directory (ie: branches, releases)
	my $treetext = "<h3>$headertype</h3>\n";
	$treetext   .= "<ul>\n";

	# relative to the $PROJECTROOT directory
	my $toptext = "<h3>" . get_link($headertype, File::Spec->catfile($treedir, 'index.html'), $PROJECTROOT) . "</h3>\n";
	$toptext   .= "<ul>\n";

	opendir(DIR, $treedir) or die "Failed to open $treedir for reading: $!\n";
	my @names = sort { versioncmp($a, $b) } grep { !/^(\..*|index\.html|latest)$/ && -d File::Spec->catdir($treedir, $_) } readdir(DIR);
	if ($treebase eq 'releases') {
		@names = reverse @names;
	} elsif ($treebase eq 'branches') {
		@names = sort {
			if ($a eq 'develop') {
				return -1;
			} elsif ($b eq 'develop') {
				return 1;
			}
			return 0;
		} @names;
	}

	for my $name (@names) {
		my $releasedir = File::Spec->catdir($treedir, $name);
		next unless (-d $releasedir);

		$treetext .= "<li>" . get_link($name, File::Spec->catfile($releasedir, 'index.html'), $treedir) . "<br>\n";

		$toptext .= "	<li>" . get_link($name, File::Spec->catfile($releasedir, 'index.html'), $PROJECTROOT) . "</li>\n";

		opendir(SUBDIR, $releasedir) or die "Failed to open $releasedir for reading: $!\n";
		my @docdirs = sort {
			if ($a eq 'javadoc') {
				return -1;
			} elsif ($b eq 'javadoc') {
				return 1;
			} else {
				return $a cmp $b;
			}
		} grep { !/^index\.(html|pdf)$/ } grep { !/^\./ } readdir(SUBDIR);
		closedir(SUBDIR) or die "Failed to close $releasedir: $!\n";

		my $header = $headertype . ' - ' . $name;

		my $releasetext = "\n<h4>$header</h4>\n";
		$releasetext   .= "<ul>\n";

		for my $docname (@docdirs) {
			my $docdir = File::Spec->catdir($releasedir, $docname);

			my $description = $DESCRIPTIONS->{$docname};
			if (not defined $description) {
				$description = $docname;
			}

			#$treetext    .= "$description (";
			$releasetext .= "	<li>$description (";

			if ($docname eq 'javadoc') {
				#$treetext    .= get_link('html', File::Spec->catfile($docdir, 'index.html'), $treedir);
				$treetext    .= get_link($description, File::Spec->catfile($docdir, 'index.html'), $treedir);
				$releasetext .= get_link('html', File::Spec->catfile($docdir, 'index.html'), $releasedir);
			} else {
				my $pdf = File::Spec->catfile($docdir, $docname . '.pdf');

				$treetext .= get_link($description, File::Spec->catfile($docdir, $docname . '.html'), $treedir);

				if (-f $pdf) {
					#$treetext    .= get_link('pdf', File::Spec->catfile($docdir, $docname . '.pdf'), $treedir) . ', ';
					$treetext    .= ' (' . get_link('pdf', File::Spec->catfile($docdir, $docname . '.pdf'), $treedir) . ')';
					$releasetext .= get_link('pdf', File::Spec->catfile($docdir, $docname . '.pdf'), $releasedir) . ', ';
				}
				$releasetext .= get_link('html', File::Spec->catfile($docdir, $docname . '.html'), $releasedir);
			}
			#$treetext  .= '), ';
			$treetext    .= ', ';
			$releasetext .= ")</li>\n";
		}
		$treetext =~ s/, $/\n/;
		$treetext .= "</li>\n";

		$releasetext .= "</ul>\n";

		write_html($header, $releasetext, File::Spec->catfile($releasedir, 'index.html'));
	}

	$treetext .= "\n</ul>\n";
	$toptext .= "</ul>\n";

	write_html($headertype, $treetext, File::Spec->catfile($treedir, 'index.html'));

	closedir(DIR) or die "Failed to close $treedir: $!\n";

	if ($treebase eq 'releases') {
		my $latestdir = File::Spec->catdir($treedir, 'latest');
		if (-e $latestdir) {
			unlink($latestdir) or die "Unable to unlink $latestdir: $!\n";
		}
		if (@names > 0) {
			symlink($names[0], $latestdir);
		}
	}

	return $toptext;
}

sub write_html {
	my $title = shift;
	my $text  = shift;
	my $file  = shift;

	my $dirname = dirname($file);
	my $relative_top = File::Spec->abs2rel(File::Spec->catfile($PROJECTROOT, 'index.html'), $dirname);

	open(FILEOUT, '+>', $file .'.new') or die "Failed to open $file for writing: $!\n";
	print FILEOUT <<END;
<!DOCTYPE html>
<html lang="en">
	<head>
		<meta charset="utf-8">
		<meta http-equiv="X-UA-Compatible" content="IE=edge">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<title>$title</title>
		<link rel="stylesheet" href="//maxcdn.bootstrapcdn.com/bootstrap/${BOOTSTRAPVERSION}/css/bootstrap.min.css">
		<link rel="stylesheet" href="//maxcdn.bootstrapcdn.com/bootstrap/${BOOTSTRAPVERSION}/css/bootstrap-theme.min.css">
		<style type="text/css">
			body {
				padding-top: 50px;
			}
		</style>
	</head>
	<body>
		<nav class="navbar navbar-inverse navbar-fixed-top">
			<div class="container">
				<div class="navbar-header">
					<a class="navbar-brand" href="$relative_top">OpenNMS Documentation</a>
				</div>
				<!--
				<div id="navbar" class="collapse navbar-collapse">
					<ul class="nav navbar-nav">
						<li class="active"><a href="#">Home</a></li>
						<li><a href="#about">About</a></li>
						<li><a href="#contact">Contact</a></li>
					</ul>
				</div>
				-->
			</div>
		</nav>

		<div class="container">
END

	print FILEOUT $text;
	print FILEOUT <<END;
		</div>
		<script src="//maxcdn.bootstrapcdn.com/bootstrap/${BOOTSTRAPVERSION}/js/bootstrap.min.js"></script>
	</body>
</html>
END
	close(FILEOUT) or die "Failed to close $file: $!\n!";

	if (-e $file) {
		unlink($file) or die "Failed to unlink $file: $!\n";
	}
	link($file . '.new', $file) or die "Failed to link $file.new to $file: $!\n";
	unlink($file . '.new') or die "Failed to remove $file.new: $!\n";
}

sub process_asciidoc_docdir {
	my $docdir = shift;

	opendir(DIR, $docdir) or die "Failed to open $docdir for reading: $!\n";
	my @guides = sort grep { !/^\.\.?$/ } readdir(DIR);
	closedir(DIR) or die "Failed to close $docdir: $!\n";

	for my $dir (@guides) {
		copy_asciidoc_guide($docdir, $dir);
	}
}

sub copy_asciidoc_guide {
	my $sourcedir = shift;
	my $guide     = shift;

	my $from = File::Spec->catdir($sourcedir, $guide);
	my $to = File::Spec->catdir($INSTALLDIR, $guide);

	print "- Copying $guide to '$to'... ";
	find({
		wanted => sub {
			return unless (-f $File::Find::name);
			my $rel = File::Spec->abs2rel($_, $from);
			return unless ($rel =~ /^(index\.(html|pdf)$|images\/)/);
			return if ($rel =~ /\.adoc$/);

			my $fromfile = File::Spec->catfile($from, $rel);
			my $tofile = File::Spec->catfile($to, $rel);

			my $dirname = dirname($tofile);
			if (not -d $dirname) {
				mkpath($dirname);
				#system('chmod', '755', $dirname) == 0 or die "Failed to fix ownership on $dirname: $!\n";
			}

			#print "- copy: $fromfile -> $tofile\n";
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
	print "done\n";
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

	opendir(DIR, $from) or die "Failed to open $from for reading: $!\n";
	my @files = sort grep { /\.(pdf|html)$/ } readdir(DIR);
	closedir(DIR) or die "Failed to close $from: $!\n";

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

		print "- Processing $name... ";

		my $mappedname = (exists $mapping->{$name}? $mapping->{$name} : $name);
		my $to = File::Spec->catdir($INSTALLDIR, $mappedname);

		for my $extension ('pdf', 'html') {
			my $fromfile = File::Spec->catfile($from, $name . '.' . $extension);
			my $tofile   = File::Spec->catfile($to, 'index.' . $extension);

			next unless (-f $fromfile);

			my $dirname  = dirname($tofile);
			if (not -d $dirname) {
				mkpath($dirname);
				#system('chmod', '755', $dirname) == 0 or die "Failed to fix ownership on $dirname: $!\n";
			}

			copy($fromfile, $tofile) or die "Failed to copy '$fromfile' to '$tofile': $!\n";
			#system('chmod', '644', $tofile) or die "Failed to fix ownership on $tofile: $!\n";

			symlink('index.' . $extension, File::Spec->catfile($to, $mappedname . '.' . $extension));

			if (defined $common) {
				symlink('../.common', File::Spec->catfile($to, 'common'));
			}
		}

		print "done\n";
		$done->{$name}++;
	}
}

sub process_javadoc_docdir {
	my $from = File::Spec->catdir(shift);
	my $to   = File::Spec->catdir($INSTALLDIR, 'javadoc');
	mkpath($to) unless (-d $to);

	print "- Copying javadoc to '$to'... ";
#	find({
#		wanted => sub {
#			my $rel = File::Spec->abs2rel($File::Find::name, $from);
#			return unless (-f $File::Find::name);
#
#			my $fromfile = File::Spec->catfile($from, $rel);
#			my $tofile = File::Spec->catfile($to, $rel);
#
#			my $dirname = dirname($tofile);
#			if (not -d $dirname) {
#				mkpath($dirname);
#				#system('chmod', '755', $dirname) or die "Failed to fix ownership on $dirname: $!\n";
#			}
#
#			#print "- copy: $fromfile -> $tofile\n";
#			copy($fromfile, $tofile) or die "Failed to copy '$fromfile' to '$tofile': $!\n";
#			#system('chmod', '644', $tofile) == 0 or die "Failed to fix ownership on $tofile: $!\n";
#		},
#		bydepth => 1,
#		follow => 1,
#		no_chdir => 1,
#	}, $from);
	system('rsync', '-r', '--delete', $from.'/', $to.'/') == 0 or die "Failed to sync from $from to $to: $!\n";
	print "done\n";
}

sub fix_permissions {
	my $dir = shift;
	#system('chown', '-R', 'opennms:opennms', $dir) == 0 or die "Failed to fix ownership on $dir: $!\n";
	#system('chmod', '-R', 'a+r', $dir) == 0 or die "Failed to fix permissions on $dir: $!\n";
}

sub usage {
	print STDERR <<END;
usage: $0 [--root=/path/to/doc/root] [--branch=branch_name] <docs> <project> <version>

OPTIONS:

	--root          the base path for documentation
	--branch        the branch name for documentation

END

	exit 1;
}

# from Sort::Versions 1.5
sub versioncmp( $$ ) {
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
