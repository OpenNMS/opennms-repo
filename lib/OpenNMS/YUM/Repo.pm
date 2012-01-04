package OpenNMS::YUM::Repo;

use 5.008008;
use strict;
use warnings;

use Carp;
#use Cwd qw(abs_path);
use Cwd;
use File::Basename;
use File::Copy qw();
use File::Find;
use File::Path;
use File::Spec;

use OpenNMS::YUM::RPM;

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

	$base =~ s/\/$//;

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

sub path() {
	my $self = shift;
	return File::Spec->catfile($self->releasedir, $self->platform);
}

sub releasedir() {
	my $self = shift;
	return File::Spec->catfile($self->base, $self->release);
}

sub abs_path() {
	my $self = shift;
	return Cwd::abs_path($self->path);
}

sub copy {
	my $self = shift;
	my $newbase = shift;
	if (not defined $newbase) {
		return undef;
	}

	my $rsync = `which rsync 2>/dev/null`;
	if ($? != 0) {
		carp "Unable to locate rsync!";
		return undef;
	}
	chomp($rsync);

	my $repo = OpenNMS::YUM::Repo->new($newbase, $self->release, $self->platform);
	mkpath($repo->path);
	system($rsync, "-avr", $self->path . "/", $repo->path . "/");

	return $repo;
}

sub delete {
	my $self = shift;

	rmtree($self->path) or die "Unable to remove " . $self->path;
	rmdir($self->releasedir);
	rmdir($self->base);
	return 1;
}

sub get_rpms {
	my $self = shift;

	my $rpms = [];
	find({ wanted => sub {
		return unless ($File::Find::name =~ /\.rpm$/);
		return unless (-e $File::Find::name);
		my $rpm = OpenNMS::YUM::RPM->new($File::Find::name);
		push(@{$rpms}, $rpm);
	}, no_chdir => 1}, $self->path);
	return $rpms;
}

sub install_rpm($$) {
	my $self   = shift;
	my $rpm    = shift;
	my $topath = shift;

	return $rpm->copy(File::Spec->catfile($self->abs_path, $topath));
}

sub link_rpm($$) {
	my $self   = shift;
	my $rpm    = shift;
	my $topath = shift;

	return $rpm->link(File::Spec->catfile($self->abs_path, $topath));
}

sub find_newest_rpm_by_name {
	my $self      = shift;
	my $name      = shift;

	my $rpm = undef;
	my $rpms = $self->get_rpms();
	for my $local_rpm (@{$rpms}) {
		next unless ($local_rpm->name eq $name);

		if (not defined $rpm or $local_rpm->is_newer_than($rpm)) {
			$rpm = $local_rpm;
		}
	}
	return $rpm;
}

sub share_rpm($$) {
	my $self      = shift;
	my $from_repo = shift;
	my $rpm       = shift;
	my $topath    = File::Spec->catfile($self->path, dirname($rpm->relative_path($from_repo->abs_path)));

	my $local_rpm = $self->find_newest_rpm_by_name($rpm->name);

	if ($rpm->is_newer_than($local_rpm)) {
		$rpm->link($topath);
	}
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
