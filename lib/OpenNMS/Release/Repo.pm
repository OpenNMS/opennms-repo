package OpenNMS::Release::Repo;

use 5.008008;
use strict;
use warnings;

=head1 NAME

OpenNMS::Release::Repo - Perl extension that represents a package repository

=head1 SYNOPSIS

  use OpenNMS::Release::Repo;

=head1 DESCRIPTION

This represents an individual package repository.

=cut

our $VERSION = '2.0';

=head1 CONSTRUCTOR

OpenNMS::Release::Repo-E<gt>new();

Create a new Repo object.  You can add and remove packages to/from it, re-index it, and so on.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};

	bless($self);
	return $self;
}

=head1 METHODS

=cut

1;

__END__
=head1 AUTHOR

Benjamin Reed E<lt>ranger@opennms.orgE<gt>
Matt Brozowski E<lt>brozow@opennms.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by The OpenNMS Group, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
