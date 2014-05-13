package OpenNMS::Release::RPMVersion;

use 5.008008;
use strict;
use warnings;

use Carp;

use OpenNMS::Util 2.5.0;
use Module::Load::Conditional qw[can_load];

use base qw(OpenNMS::Release::Version);

=head1 NAME

OpenNMS::Release::RPMVersion - Perl extension for manipulating RPM Versions

=head1 SYNOPSIS

  use OpenNMS::Release::RPMVersion;


=head1 DESCRIPTION

This is just a perl module for manipulating RPM versions.

=cut

our $VERSION = 2.5.0;
our $RPMVER  = undef;
our $USEPERL = undef;

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

	my $self    = bless($class->SUPER::new($version, $release, $epoch), $class);

	if (can_load( modules => { 'RPM::VersionCompare' => undef } )) {
		require RPM::VersionCompare;
		RPM::VersionCompare->import();
		$USEPERL = 1;
	}

	if (not defined $RPMVER and not defined $USEPERL) {
		$RPMVER = find_executable('rpmver');
		if (not defined $RPMVER) {
			croak "Unable to locate \`rpmver\` executable: $!\n";
		}
	}

	return $self;
}

=head1 METHODS

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

	if ($USEPERL) {
		return RPM::VersionCompare::labelCompare($thisversion, $thatversion);
	} else {
		if (system("$RPMVER '$thisversion' '=' '$thatversion'") == 0) {
			return 0;
		}
		if (system("$RPMVER '$thisversion' '<' '$thatversion'") == 0) {
			return -1;
		} else {
			return 1;
		}
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
