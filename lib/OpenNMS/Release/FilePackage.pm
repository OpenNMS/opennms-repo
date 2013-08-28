package OpenNMS::Release::FilePackage;

use 5.008008;
use strict;
use warnings;

use Carp;
use Cwd;
use File::Basename;
use File::Copy qw();
use IO::Handle;
use Expect;

use base qw(OpenNMS::Release::Package);

use OpenNMS::Release::Version 2.6.2;

=head1 NAME

OpenNMS::Release::FilePackage - Perl extension for manipulating files

=head1 SYNOPSIS

	use OpenNMS::Release::FilePackage;

	my $tarball = OpenNMS::Release::FilePackage->new("path/to/foo-1.0.tar.gz");

=head1 DESCRIPTION

This is just a perl module for manipulating files, including version comparisons, path comparisons, and other miscellaneous things.

=cut

our $VERSION = '2.6.3';

=head1 CONSTRUCTOR

OpenNMS::Release::FilePackage->new($path)

Given a path to a file, create a new OpenNMS::Release::FilePackage object.  The file must exist.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $path = shift;

	if (not defined $path) {
		carp "You did not provide a path!";
		return undef;
	}

	my $name	= undef;
	my $version     = undef;
	my $release     = undef;
	my $extension   = undef;
	my $compression = undef;
	my $type        = undef;

	my $filename    = basename($path);

	if ($filename =~ s/\.(tar.gz|tgz)$//) {
		$extension   = $1;
		$compression = 'gzip';
		$type        = 'tarball';
	} elsif ($filename =~ s/\.(tar.bz2|tbz2)$//) {
		$extension   = $1;
		$compression = 'bzip2';
		$type        = 'tarball';
	} elsif ($filename =~ s/\.(zip)$//) {
		$extension   = $1;
		$compression = 'zip';
		$type        = 'zip';
	} else {
		carp "Unable to determine if $filename is a supported file";
		return undef;
	}

	if ($filename =~ /^(.*)-(\d[^-]*?)-(\d[^-]*?)$/) {
	# look for name-version-release first
	($name, $version, $release) = ($1, $2, $3);
	} elsif ($filename =~ /^(.*)-(\d[^\-]*?)$/) {
	# then look for name-version
	($name, $version, $release) = ($1, $2, 0);
	} else {
	# give up and set version and release to 0
	($name, $version, $release) = ($filename, 0, 0);
	}

	$version = OpenNMS::Release::Version->new($version, $release);

	my $self = bless($class->SUPER::new($path, $name, $version, $type), $class);
	$self->{EXTENSION} = $extension;
	$self->{COMPRESSION} = $compression;

	return $self;
}

=head1 METHODS

=head2 * extension

Get the extension for this file.

=cut

sub extension {
	my $self = shift;
	return $self->{EXTENSION};
}

=head2 * compression

Get the compression type for this file (gzip, bzip2, zip).

=cut

sub compression {
	my $self = shift;
	return $self->{COMPRESSION};
}

=head2 * type

Get the file type for this file (tarball, zip).

=cut

sub type {
	return shift->arch;
}

1;
__END__
=head1 AUTHOR

Benjamin Reed, E<lt>ranger@opennms.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by The OpenNMS Group, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
