package OpenNMS::YUM::Repo;

use 5.008008;
use strict;
use warnings;

use Carp;
#use Cwd qw(abs_path);
use Cwd;

=head1 NAME

OpenNMS::YUM::Repo - Perl extension that represents a YUM repository

=head1 SYNOPSIS

  use OpenNMS::YUM::Repo;

=head1 DESCRIPTION

=cut

our $VERSION = '0.01';

=head1 CONSTRUCTOR

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};

	my $base     = shift;
	my $release  = shift;
	my $platform = shift;

	if (not defined $base) {
		carp "You did not provide a base path!";
		return undef;
	}
	if (not defined $release) {
		carp "You did not specify a release!";
		return undef;
	}
	if (not defined $platform) {
		carp "You did not specify a platform!";
		return undef;
	}

	$self->{BASE}     = $base;
	$self->{RELEASE}  = $release;
	$self->{PLATFORM} = $platform;

	bless($self);
	return $self;
}

sub base {
	my $self = shift;
	if (@_) { $self->{BASE} = shift }
	return $self->{BASE};
}

sub release {
	my $self = shift;
	if (@_) { $self->{RELEASE} = shift }
	return $self->{RELEASE};
}

sub platform {
	my $self = shift;
	if (@_) { $self->{PLATFORM} = shift }
	return $self->{PLATFORM};
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!


=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

A. U. Thor, E<lt>ranger@localdomainE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by A. U. Thor

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
