package OpenNMS::Release::Version;

use 5.008008;
use strict;
use warnings;

use Carp;

=head1 NAME

OpenNMS::Release::Version - Perl extension for manipulating Versions

=head1 SYNOPSIS

  use OpenNMS::Release::Version;


=head1 DESCRIPTION

This is just a perl module for manipulating package versions.

=cut

our $VERSION = '2.0';

my $CACHE_HITS = 0;
my $CACHE_MISSES = 0;
my $COMPARE_TO_CACHE = {};

=head1 CONSTRUCTOR

OpenNMS::Release::Version->new($version, $release, [$epoch])

Given a version, release, and epoch, create a version object.

=cut

sub new {
	my $proto   = shift;
	my $class   = ref($proto) || $proto;
	my $self    = {};

	my $version = shift;
	my $release = shift;
	my $epoch   = shift;

	if (not defined $version or not defined $release) {
		carp "You must pass at least a version and release!";
		return undef;
	}

	$self->{VERSION} = $version;
	$self->{RELEASE} = $release;
	$self->{EPOCH}   = $epoch;

	bless($self);
	return $self;
}

=head1 METHODS

=head2 * epoch

The epoch.  If no epoch is set, returns undef.

=cut

sub epoch {
	my $self = shift;
	return $self->{EPOCH};
}

=head2 * epoch_int

The epoch.  If no epoch is set, returns the default epoch, 0.

=cut

sub epoch_int() {
	my $self = shift;
	return 0 unless (defined $self->epoch);
	return $self->epoch;
}

=head2 * version

The version. This is generally the same as the version of the
upstream software that was packaged.

=cut

sub version {
	my $self = shift;
	return $self->{VERSION};
}

=head2 * release

The release. This is generally a number determined by the packager
to track changes to the package, independent of version changes in the software
that is packaged.

=cut

sub release {
	my $self = shift;
	return $self->{RELEASE};
}

=head2 * full_version

Returns the complete version string, in the form: C<epoch:version-release>

=cut

sub full_version {
	my $self = shift;
	return $self->epoch_int . ':' . $self->version . '-' . $self->release;
}

=head2 * display_version

Returns the complete version string, just like full_version, expect it excludes
the epoch if there is no epoch in the version.

=cut

sub display_version {
	my $self = shift;
	return $self->epoch_int? $self->full_version : $self->version . '-' . $self->release;
}

=head2 * _compare_to($version)

Given a version, performs a cmp-style comparison, for use in sorting.
Must be implemented in subclasses.

=cut

sub _compare_to {
	my $this = shift;
	my $that = shift;

	return 1 unless (defined $that);

	if ($this->epoch_int != $that->epoch_int) {
		return _compare_version($this->epoch_int, $that->epoch_int);
	}

	if ($this->version ne $that->version) {
		return _compare_version($this->version, $that->version);
	}

	if ($this->release ne $that->release) {
		return _compare_version($this->release, $that->release);
	}

	return 0;
}

sub _compare_version {
	my $ver_a = shift;
	my $ver_b = shift;

	#print STDERR "\n_compare_version($ver_a, $ver_b)\n";

	my @a = split(/[^[:alnum:]]/, $ver_a);
	my @b = split(/[^[:alnum:]]/, $ver_b);

	my $length_a = scalar(@a);
	my $length_b = scalar(@b);

	my $length = ($length_a >= $length_b)? $length_a : $length_b;

	for my $i (0 .. ($length - 1)) {
		#print STDERR "\na = $a[$i], b = $b[$i]\n";
		next unless (defined $a[$i] or defined $b[$i]);

		return -1 unless (defined $a[$i]);
		return  1 unless (defined $b[$i]);

		my $comparison = $a[$i] cmp $b[$i];
		return $comparison if ($comparison != 0);
	}

	return 0;
}

=head2 * compare_to($version)

Given a version, performs a cmp-style comparison, for use in sorting. Catches by default,
calling _compare_to for the actual implementation of comparison.

=cut

# -1 = self before(compared)
#  0 = equal
#  1 = self after(compared)
sub compare_to {
	my $this = shift;
	my $that = shift;

	my $thisversion = $this->full_version;
	my $thatversion = $that->full_version;

	if (exists $COMPARE_TO_CACHE->{$thisversion}->{$thatversion}) {
		$CACHE_HITS++;
		return $COMPARE_TO_CACHE->{$thisversion}->{$thatversion};
	}

	my $ret = $this->_compare_to($that);

	$CACHE_MISSES++;
	$COMPARE_TO_CACHE->{$thisversion}->{$thatversion} = $ret;

	return $ret;
}

=head2 * equals($version)

Given a version object, returns true if both versions are the same.

=cut

sub equals($) {
	my $self      = shift;
	my $compareto = shift;

	return $self->compare_to($compareto) == 0;
}

=head2 * is_newer_than($version)

Given a version object, returns true if the current version is newer than the
given version.

=cut

sub is_newer_than($) {
	my $self      = shift;
	my $compareto = shift;

	return $self->compare_to($compareto) == 1;
}

=head2 * is_older_than($version)

Given a version object, returns true if the current version is older than the
given version.

=cut

sub is_older_than($) {
	my $self      = shift;
	my $compareto = shift;

	return $self->compare_to($compareto) == -1;
}

=head2 * to_string

Returns a string representation of the version, suitable for printing.

=cut

sub to_string() {
	my $self = shift;
	return $self->display_version;
}

sub stats {
	my $class = shift;
	return {
		cache_hits => $CACHE_HITS,
		cache_misses => $CACHE_MISSES
	};
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
