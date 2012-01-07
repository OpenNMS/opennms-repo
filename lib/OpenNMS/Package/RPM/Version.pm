package OpenNMS::Package::RPM::Version;

use 5.008008;
use strict;
use warnings;

use Carp;

=head1 NAME

OpenNMS::Package::RPM::Version - Perl extension for manipulating RPM Versions

=head1 SYNOPSIS

  use OpenNMS::Package::RPM::Version;


=head1 DESCRIPTION

This is just a perl module for manipulating RPM versions.

=cut

our $VERSION = '0.1';

my $CACHE_HITS = 0;
my $CACHE_MISSES = 0;
my $COMPARE_TO_CACHE = {};

=head1 CONSTRUCTOR

OpenNMS::Package::RPM::Version->new($version, $release, [$epoch])

Given a version, release, and optional epoch, create a version object.

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
to track changes to the RPM, independent of version changes in the software
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

=head2 * compare_to($version)

Given a version, performs a cmp-style comparison, for use in sorting.

=cut

# -1 = self before(compared)
#  0 = equal
#  1 = self after(compared)
sub compare_to {
	my $self       = shift;
	my $compareto  = shift;
	my $use_rpmver = shift || 1;

	my $compareversion = $compareto->full_version;
	my $selfversion    = $self->full_version;

	if (exists $COMPARE_TO_CACHE->{$compareversion}->{$selfversion}) {
		$CACHE_HITS++;
		return $COMPARE_TO_CACHE->{$compareversion}->{$selfversion};
	}

	my $rpmver = `which rpmver 2>/dev/null`;
	chomp($rpmver);
	if ($? == 0 && $use_rpmver) {
		# we have rpmver, defer to it

		if (system("$rpmver '$compareversion' '=' '$selfversion'") == 0) {
			return _cache_comparison($compareversion, $selfversion, 0);
		}
		my $retval = (system("$rpmver '$compareversion' '<' '$selfversion'") >> 8);
		return _cache_comparison($compareversion, $selfversion, 1) if ($retval == 0);
		return _cache_comparison($compareversion, $selfversion, -1);
	}

	# otherwise, attempt to parse ourselves, this will probably
	# not handle all corner cases

	carp "rpmver not found, attempting to parse manually. This is generally a bad idea.";

	return _cache_comparison($compareversion, $selfversion, 1) unless (defined $compareto);

	if ($compareto->epoch_int != $self->epoch_int) {
		# if the compared is lower than the self, return 1 (after)
		return _cache_comparison($compareversion, $selfversion, ($compareto->epoch_int < $self->epoch_int) ? 1 : -1);
	}

	if ($compareto->version ne $self->version) {
		return _cache_comparison($compareversion, $selfversion, _compare_version($compareto->version, $self->version));
	}

	if ($compareto->release ne $self->release) {
		return _cache_comparison($compareversion, $selfversion, _compare_version($compareto->release, $self->release));
	}

	return _cache_comparison($compareversion, $selfversion, 0);
}

sub _compare_version {
	my $ver_a = shift;
	my $ver_b = shift;

	my @a = split(!/[[:alnum:]]/, $ver_a);
	my @b = split(!/[[:alnum:]]/, $ver_b);

	my $length_a = length(@a);
	my $length_b = length(@b);

	my $length = ($length_a >= $length_b)? $length_a : $length_b;

	for my $i (0 .. $length) {
		next if ($a[$i] eq $b[$i]);
		my $comparison = $a[$i] cmp $b[$i];
		return $comparison if ($comparison != 0);
	}

	return 0;
}

sub _cache_comparison {
	my $compareversion = shift;
	my $selfversion    = shift;
	my $result         = shift;

	$CACHE_MISSES++;
	$COMPARE_TO_CACHE->{$compareversion}->{$selfversion} = $result;
	return $result;
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
