package OpenNMS::Release::RPMVersion;

use 5.008008;
use strict;
use warnings;

use Carp;

use base qw(OpenNMS::Release::Version);

=head1 NAME

OpenNMS::Release::RPMVersion - Perl extension for manipulating RPM Versions

=head1 SYNOPSIS

  use OpenNMS::Release::RPMVersion;


=head1 DESCRIPTION

This is just a perl module for manipulating RPM versions.

=cut

our $VERSION = '0.1';
our $RPMVER  = undef;

my $CACHE_HITS = 0;
my $CACHE_MISSES = 0;
my $COMPARE_TO_CACHE = {};

=head1 CONSTRUCTOR

OpenNMS::Release::RPMVersion->new($version, $release, [$epoch])

Given a version, release, and optional epoch, create a version object.

=cut

sub new {
	my $proto   = shift;
	my $class   = ref($proto) || $proto;

	my $version = shift;
	my $release = shift;
	my $epoch   = shift;

	my $self    = bless($class->SUPER::new($version, $release), $class);

	$self->{EPOCH} = $epoch;

	if (not defined $RPMVER) {
		$RPMVER = `which rpmver 2>/dev/null`;
		if ($? != 0) {
			croak "Unable to locate \`rpmver\` executable: $!\n";
		}
		chomp($RPMVER);
	}

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

=cut

# -1 = self before(compared)
#  0 = equal
#  1 = self after(compared)
sub _compare_to {
	my $this = shift;
	my $that = shift;

	my $thisversion = $this->full_version;
	my $thatversion = $that->full_version;

	if ($thisversion eq $thatversion) {
		return 0;
	}

	if (system("$RPMVER '$thisversion' '=' '$thatversion'") == 0) {
		return 0;
	}
	if (system("$RPMVER '$thisversion' '<' '$thatversion'") == 0) {
		return -1;
	} else {
		return 1;
	}
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
