package OpenNMS::Release::LocalPackage;

use 5.008008;
use strict;
use warnings;

use Carp;

use base qw(OpenNMS::Release::Package);

=head1 NAME

OpenNMS::Release::LocalPackage - Perl extension for manipulating packages

=head1 SYNOPSIS

  use OpenNMS::Release::LocalPackage;

  my $package = OpenNMS::Release::LocalPackage->new("path/to/foo");
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

OpenNMS::Release::LocalPackage->new($path, $name, $version, [$arch])

Given a path to a package file, name, OpenNMS::Release::Version, and optional
architecture, create a new OpenNMS::Release::LocalPackage object.

The file must be absolute, and must exist.

=cut

sub new {
	my $proto   = shift;
	my $class   = ref($proto) || $proto;
	my $path    = shift;
	my $name    = shift;
	my $version = shift;
	my $arch    = shift;

	my $self    = bless($class->SUPER::new($path, $name, $version, $arch), $class);

	if (not -e $self->path) {
		carp "package path " . $self->path . " does not exist!";
		return undef;
	}

	return $self;
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
