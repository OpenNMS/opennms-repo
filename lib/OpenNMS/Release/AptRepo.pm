package OpenNMS::Release::AptRepo;

use 5.008008;
use strict;
use warnings;

use Carp;
use Cwd;
use Data::Dumper;
use File::Basename;
use File::Copy qw();
use File::Find;
use File::Path;
use File::Spec;
use File::Temp qw(tempdir);

use OpenNMS::Util;
use OpenNMS::Release::RPM;

=head1 NAME

OpenNMS::Release::AptRepo - Perl extension that represents an Apt repository

=head1 SYNOPSIS

  use OpenNMS::Release::AptRepo;

=head1 DESCRIPTION

This represents an individual debian/apt repository.

=cut

our $VERSION = '1.0';

=head1 CONSTRUCTOR

OpenNMS::Release::AptRepo-E<gt>new();

Create a new Repo object.  You can add and remove packages to/from it, re-index it, and so on.

=over 2

=back

=cut

sub new {
	my $proto = shift;
	my $self  = $proto->SUPER::new(@_);
}

=head1 METHODS

=cut


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
