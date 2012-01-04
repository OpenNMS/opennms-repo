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

	$self->{DIRTY}    = 0;
	$self->{BASE}     = $base;
	$self->{RELEASE}  = $release;
	$self->{PLATFORM} = $platform;

	bless($self);
	return $self;
}

sub dirty {
	my $self = shift;
	if ($@) { $self->{DIRTY} = shift }
	return $self->{DIRTY};
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
	return File::Spec->catfile($self->base, $self->release, $self->platform);
}

sub releasedir() {
	my $self = shift;
	return File::Spec->catfile($self->base, $self->release);
}

sub abs_path() {
	my $self = shift;
	return Cwd::abs_path($self->path);
}

sub to_string() {
	my $self = shift;
	return $self->path;
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

sub _rpmset {
	my $self = shift;

	if (not exists $self->{RPMSET}) {
		my $rpms = [];
		find({ wanted => sub {
			return unless ($File::Find::name =~ /\.rpm$/);
			return unless (-e $File::Find::name);
			my $rpm = OpenNMS::YUM::RPM->new($File::Find::name);
			push(@{$rpms}, $rpm);
		}, no_chdir => 1}, $self->path);
		$self->{RPMSET} = OpenNMS::YUM::Repo::RPMSet->new($rpms);
	}
	return $self->{RPMSET};
	
}

sub _add_to_rpmset($) {
	my $self = shift;
	my $rpm  = shift;

	if (exists $self->{RPMSET}) {
		$self->_rpmset->add($rpm);
	}
}

sub find_all_rpms {
	my $self = shift;

	return $self->_rpmset->find_all();
}

sub find_newest_rpms {
	my $self = shift;
	return $self->_rpmset->find_newest();
}

sub find_newest_rpm_by_name {
	my $self      = shift;
	my $name      = shift;

	return $self->_rpmset->find_newest_by_name($name);
}

sub copy_rpm($$) {
	my $self   = shift;
	my $rpm    = shift;
	my $topath = shift;

	$self->dirty(1);

	my $newrpm = $rpm->copy($topath);
	$self->_add_to_rpmset($newrpm);
	return $newrpm;
}

sub symlink_rpm($$) {
	my $self   = shift;
	my $rpm    = shift;
	my $topath = shift;

	$self->dirty(1);

	my $newrpm = $rpm->symlink($topath);
	$self->_add_to_rpmset($newrpm);
	return $newrpm;
}

sub install_rpm($$) {
	my $self   = shift;
	my $rpm    = shift;
	my $topath = shift;

	my $finalpath = File::Spec->catfile($self->abs_path, $topath);
	mkpath($finalpath);
	$self->copy_rpm($rpm, $finalpath);
}

sub share_rpm($$) {
	my $self      = shift;
	my $from_repo = shift;
	my $rpm       = shift;

	my $topath_r   = dirname($rpm->relative_path($from_repo->abs_path));
	my $abs_topath = File::Spec->catfile($self->abs_path, $topath_r);

	my $local_rpm = $self->find_newest_rpm_by_name($rpm->name);

	if ($rpm->is_newer_than($local_rpm)) {
		$self->symlink_rpm($rpm, $abs_topath);
	}
}

1;

package OpenNMS::YUM::Repo::RPMSet;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};

	$self->{RPMS} = {};

	bless($self);

	if (@_) {
		$self->add(@_);
	}

	return $self;
}

sub _hash() {
	my $self = shift;
	return $self->{RPMS};
}

sub add(@) {
	my $self = shift;

	my @rpms = ();
	for my $item (@_) {
		if (ref($item) eq "ARRAY") {
			push(@rpms, @{$item});
		} else {
			push(@rpms, $item);
		}
	}
	for my $rpm (@rpms) {
		push(@{$self->_hash->{$rpm->name}}, $rpm);
		my %seen = ();
		#@{$self->_hash->{$rpm->name}} = sort { $b->compare_to($a) } grep { ! $seen{$rpm->path}++ } @{$self->_hash->{$rpm->name}};
		@{$self->_hash->{$rpm->name}} = sort { $b->compare_to($a) } @{$self->_hash->{$rpm->name}};
	}
}

sub set(@) {
	my $self = shift;
	$self->{RPMS} = {};
	$self->add(@_);
}

sub find_all() {
	my $self = shift;
	my @ret = ();
	for my $key (sort keys %{$self->_hash}) {
		push(@ret, @{$self->_hash->{$key}});
	}
	return \@ret;
}

sub find_newest() {
	my $self = shift;
	my @ret = ();
	for my $key (sort keys %{$self->_hash}) {
		push(@ret, $self->_hash->{$key}->[0]);
	}
	return \@ret;
}

sub find_by_name($) {
	my $self = shift;
	my $name = shift;
	return $self->_hash->{$name};
}

sub find_newest_by_name($) {
	my $self = shift;
	my $name = shift;
	return $self->find_by_name($name)->[0];
}

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
