#!/usr/bin/env perl -w

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
	$BRANCH

	$DOCS
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

$DOCS = shift @ARGV;
$VERSION = shift @ARGV;

if (not defined $DOCS or $DOCS eq "") {
	print STDERR "ERROR: You must specify a document directory/file and a version!\n";
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

if (! -d $ROOT) {
	print STDERR "WARNING: Creating document root: $ROOT\n";
	mkpath($ROOT);
}

if (not defined $BRANCH or $BRANCH eq "") {
	$BRANCH = undef;
	$INSTALLDIR = File::Spec->catdir($ROOT, 'releases', $VERSION);
} else {
	$BRANCHDIR = $BRANCH;
	$BRANCHDIR =~ s/[^[:alnum:]\.\-]+/-/g;
	$INSTALLDIR = File::Spec->catdir($ROOT, 'branches', $BRANCHDIR);
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
} elsif (-d File::Spec->catdir($DOCDIR, 'docs') and -f File::Spec->catfile($DOCDIR, 'docs', 'adminref.pdf')) {
	process_docbook_docdir($DOCDIR);
} elsif (-f File::Spec->catfile($DOCDIR, 'apidocs', 'index-all.html') and -f File::Spec->catfile($DOCDIR, 'apidocs', 'allclasses-frame.html')) {
	process_javadoc_docdir(File::Spec->catdir($DOCDIR, 'apidocs'));
} elsif (-f File::Spec->catfile($DOCDIR, 'index-all.html') and -f File::Spec->catfile($DOCDIR, 'allclasses-frame.html')) {
	process_javadoc_docdir($DOCDIR);
} else {
	die "Unknown documentation type: $DOCS\n";
}

update_indexes();

exit 0;

sub update_indexes {
	my $index = "";
	if (-d File::Spec->catdir($ROOT, 'releases')) {
		$index .= process_tree(File::Spec->catdir($ROOT, 'releases'));
	}

	if (-d File::Spec->catdir($ROOT, 'branches')) {
		$index .= process_tree(File::Spec->catdir($ROOT, 'branches'));
	}

	write_html('OpenNMS Documentation', $index, File::Spec->catfile($ROOT, 'index.html'));
}

sub get_link {
	my $description = shift;
	my $file        = shift;
	my $relative_to = shift;

	return "<a href=\"" . File::Spec->abs2rel($file, $relative_to) . "\">$description</a>";
}

# $ROOT / tree / release / doc
sub process_tree {
	my $treedir = shift;

	my $headertype = 'OpenNMS ' . ucfirst(lc(basename($treedir)));

	# relative to the $treedir directory (ie: branches, releases)
	my $treetext = "<h3>$headertype</h3>\n";
	$treetext   .= "<ul>\n";

	# relative to the $ROOT directory
	my $toptext = "<h3>" . get_link($headertype, File::Spec->catfile($treedir, 'index.html'), $ROOT) . "</h3>\n";
	$toptext   .= "<ul>\n";

	opendir(DIR, $treedir) or die "Failed to open $treedir for reading: $!\n";
	while (my $name = readdir(DIR)) {
		next if ($name =~ /^\.\.?$/);

		my $releasedir = File::Spec->catdir($treedir, $name);
		next unless (-d $releasedir);

		$treetext .= "<li>" . get_link($name, File::Spec->catfile($releasedir, 'index.html'), $treedir) . "<br>\n";

		$toptext .= "	<li>" . get_link($name, File::Spec->catfile($releasedir, 'index.html'), $ROOT) . "</li>\n";

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
				$treetext    .= get_link($description, File::Spec->catfile($docdir, 'index.html'), $treedir) . ', ';
				$releasetext .= get_link('html', File::Spec->catfile($docdir, 'index.html'), $releasedir);
			} else {
				my $pdf = File::Spec->catfile($docdir, $docname . '.pdf');

				$treetext .= get_link($description, File::Spec->catfile($docdir, $docname . '.html'), $treedir);

				if (-f $pdf) {
					#$treetext    .= get_link('pdf', File::Spec->catfile($docdir, $docname . '.pdf'), $treedir) . ', ';
					$treetext    .= ' (' . get_link('pdf', File::Spec->catfile($docdir, $docname . '.pdf'), $treedir) . '), ';
					$releasetext .= get_link('pdf', File::Spec->catfile($docdir, $docname . '.pdf'), $releasedir) . ', ';
				}
				$releasetext .= get_link('html', File::Spec->catfile($docdir, $docname . '.html'), $releasedir);
			}
			#$treetext  .= '), ';
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

	return $toptext;
}

sub write_html {
	my $title = shift;
	my $text  = shift;
	my $file  = shift;

	my $dirname = dirname($file);
	my $relative_top = File::Spec->abs2rel(File::Spec->catfile($ROOT, 'index.html'), $dirname);

	open(FILEOUT, '>', $file) or die "Failed to open $file for writing: $!\n";
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
			if (! -d $dirname) {
				mkpath($dirname);
			}

			#print "- copy: $fromfile -> $tofile\n";
			copy($fromfile, $tofile) or die "Failed to copy '$fromfile' to '$tofile': $!\n";

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

	my $from = File::Spec->catdir($docdir, 'docs');

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
				mkpath($dirname) unless (-d $dirname);

				copy($fromfile, $tofile) or die "Failed to copy '$fromfile' to '$tofile': $!\n";
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

			my $dirname  = dirname($tofile);
			mkpath($dirname) unless (-d $dirname);

			copy($fromfile, $tofile) or die "Failed to copy '$fromfile' to '$tofile': $!\n";

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
	my $from = shift;
	my $to   = File::Spec->catdir($INSTALLDIR, 'javadoc');
	mkpath($to) unless (-d $to);

	print "- Copying javadoc to '$to'... ";

	find({
		wanted => sub {
			return unless (-f $File::Find::name);
			my $rel = File::Spec->abs2rel($_, $from);

			my $fromfile = File::Spec->catfile($from, $rel);
			my $tofile = File::Spec->catfile($to, $rel);

			my $dirname = dirname($tofile);
			mkpath($dirname) unless (-d $dirname);

			copy($fromfile, $tofile) or die "Failed to copy '$fromfile' to '$tofile': $!\n";
		},
		bydepth => 1,
		follow => 1,
		no_chdir => 1,
	}, $from);

	print "done\n";
}

sub usage {
	print STDERR <<END;
usage: $0 [--root=/path/to/doc/root] [--branch=branch_name] <docs> <version>

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
