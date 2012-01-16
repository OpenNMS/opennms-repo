package OpenNMS::Release::FileRepo;

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
use IO::Handle;

use OpenNMS::Util;
use OpenNMS::Release::FilePackage;
use OpenNMS::Release::PackageSet;

use base qw(OpenNMS::Release::Repo);

=head1 NAME

OpenNMS::Release::FileRepo - Perl extension that represents a source repository

=head1 SYNOPSIS

  use OpenNMS::Release::FileRepo;

=head1 DESCRIPTION

This represents an individual source repository.

=cut

our $VERSION = v2.1;

=head1 CONSTRUCTOR

OpenNMS::Release::FileRepo-E<gt>new($base);

Create a new Repo object.  You can add and remove tarballs to/from it, re-index it, and so on.

=over 2

=item base - the top-level path for the repository

=back

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $base      = shift;

	my $self = bless($proto->SUPER::new($base), $class);

	return $self;
}

sub new_with_base($) {
	my $self = shift;
	my $base = shift;

	return OpenNMS::Release::FileRepo->new($base);
}

=head1 METHODS

=cut

=head2 * path

The path of the repository.

=cut

sub path() {
	my $self = shift;
	return $self->base;
}

=head2 * to_string

A convenient way of displaying the repository.

=cut

sub to_string() {
	my $self = shift;
	return $self->path;
}

sub _packageset {
	my $self = shift;

	my @packages = ();
	find({ wanted => sub {
		return unless ($File::Find::name =~ /\.(tar.gz|tgz|tar.bz2|tbz2)$/);
		return unless (-e $File::Find::name);
		my $package = OpenNMS::Release::FilePackage->new($File::Find::name);
		push(@packages, $package);
	}, no_chdir => 1}, $self->path);
	return OpenNMS::Release::PackageSet->new(\@packages);
	
}

=head2 * index({options})

No-op, source repositories don't get indexed.

=cut

sub index($) {
	return 1;
}

1;

__END__
=head1 AUTHOR

Benjamin Reed E<lt>ranger@opennms.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by The OpenNMS Group, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
