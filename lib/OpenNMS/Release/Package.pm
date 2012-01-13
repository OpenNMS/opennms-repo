package OpenNMS::Release::Package;

use 5.008008;
use strict;
use warnings;

use Carp;
use Cwd;
use File::Basename;
use File::Copy qw();
use Expect;

use base qw(OpenNMS::Release::File);

use OpenNMS::Release::Version;

=head1 NAME

OpenNMS::Release::Package - Perl extension for manipulating packages

=head1 SYNOPSIS

  use OpenNMS::Release::Package;

  my $package = OpenNMS::Release::Package->new("path/to/foo");
  if ($package->is_in_repo("path/to")) {
    print "all good!"
  }

=head1 DESCRIPTION

This is just a perl module for manipulating packages, including
version comparisons, path comparisons, and other miscellaneous
things.

=cut

our $VERSION = '2.1';

=head1 CONSTRUCTOR

OpenNMS::Release::Package->new($path, $name, $version, [$arch])

Given a path to a package file, name, OpenNMS::Release::Version, and optional
architecture, create a new OpenNMS::Release::Package object.

The file must be absolute.

=cut

sub new {
	my $proto   = shift;
	my $class   = ref($proto) || $proto;
	my $path    = shift;
	my $self    = bless($class->SUPER::new($path), $class);

	my $name    = shift;
	my $version = shift;
	my $arch    = shift || 'unknown';

	if (not defined $version) {
		carp "You must provide at least a path, name, and OpenNMS::Release::Version!";
		return undef;
	}

	$self->{NAME}    = $name;
	$self->{VERSION} = $version;
	$self->{ARCH}    = $arch;

	return $self;
}

=head1 METHODS

=head2 * name

The name of the package, i.e., "opennms".

=cut

sub name {
	my $self = shift;
	return $self->{NAME};
}

=head2 * version

The package version, as an OpenNMS::Release::Version object.

=cut

sub version {
	my $self = shift;
	return $self->{VERSION};
}

=head2 * arch

The package arch, as an OpenNMS::Release::Version object.

=cut

sub arch {
	my $self = shift;
	return $self->{ARCH};
}

=head2 * compare_to($package)

Given a package, performs a cmp-style comparison on the packages' name and version, for
use in sorting.

=cut

# -1 = self before(compared)
#  0 = equal
#  1 = self after(compared)
sub compare_to {
	my $this = shift;
	my $that = shift;

	return 1 unless (defined $that);

	if ($this->name ne $that->name) {
		return $this->name cmp $that->name;
	}

	my $thisversion = $this->version;
	my $thatversion = $that->version;

	my $ret = $thisversion->compare_to($thatversion);

	if ($ret == 0 and $this->arch ne $that->arch) {
		return $this->arch cmp $that->arch;
	}

	return $ret;
}

=head2 * equals($package)

Given a package, returns true if both packages have the same name and version.

=cut

sub equals($) {
	my $this = shift;
	my $that = shift;

	return int($this->compare_to($that) == 0);
}

=head2 * is_newer_than($package)

Given a package, returns true if the current package is newer than the
given package, and they have the same name.

=cut

sub is_newer_than($) {
	my $this = shift;
	my $that = shift;

	if ($this->name ne $that->name) {
		croak "You can't compare 2 different package names with is_newer_than! (" . $this->name . " != " . $that->name .")";
	}
	if ($this->arch ne $that->arch) {
		croak "You can't compare 2 different package architectures with is_newer_than! (" . $this->to_string . " != " . $that->to_string .")";
	}
	return int($this->compare_to($that) == 1);
}

=head2 * is_older_than($package)

Given a package, returns true if the current package is older than the
given package, and they have the same name.

=cut

sub is_older_than($) {
	my $this = shift;
	my $that = shift;

	if ($this->name ne $that->name) {
		croak "You can't compare 2 different package names with is_older_than! (" . $this->name . " != " . $that->name .")";
	}
	if ($this->arch ne $that->arch) {
		croak "You can't compare 2 different package architectures with is_older_than! (" . $this->to_string . " != " . $that->to_string .")";
	}
	return int($this->compare_to($that) == -1);
}

=head2 * delete

Delete the package from the filesystem.

=cut

sub delete() {
	my $self = shift;
	return unlink($self->path);
}

=head2 * sign($id, $password)

Given a GPG id and password, sign (or resign) the package.

=cut

sub sign ($$) {
	my $self         = shift;
	my $gpg_id       = shift;
	my $gpg_password = shift;

	croak "You must implement this in your subclass!";
}

=head2 * to_string

Returns a string representation of the package, suitable for printing.

=cut

sub to_string() {
	my $self = shift;
	return $self->name . '-' . $self->version->full_version . ' (' . $self->path . ')';
}

1;
__END__
=head1 AUTHOR

Benjamin Reed, E<lt>ranger@opennms.orgE<gt>
Matt Brozowski, E<lt>brozow@opennms.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by The OpenNMS Group, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
