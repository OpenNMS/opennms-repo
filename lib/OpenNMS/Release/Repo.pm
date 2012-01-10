package OpenNMS::Release::Repo;

use 5.008008;
use strict;
use warnings;

use Carp;
use File::Path;
use File::Basename;

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

sub dirty {
	my $self = shift;
	if (@_) { $self->{DIRTY} = shift }
	return $self->{DIRTY};
}

sub clear_cache() {
	my $self = shift;
	return delete $self->{PACKAGESET};
}

sub copy() {
	croak "You must implement this in your subclass!";
}

=head2 * create_temporary

Creates a temporary repository that is a copy of the current repository.
This temporary repository is automatically deleted on exit of the calling
program.

=cut

sub create_temporary {
	my $self = shift;

	# create a temporary directory at the same level as the current base
	my $newbase = tempdir('.repoXXXXXX', DIR => $self->abs_base, CLEANUP => 1);
	return $self->copy($newbase);
}

sub _get_fs_for_path($) {
	my $self = shift;
	my $path = shift;

	my $df = `which df 2>/dev/null`;
	if ($? == 0) {
		chomp($df);
		open(OUTPUT, "$df -h '$path' |") or croak "unable to run 'df -h $path': $!";
		<OUTPUT>;
		my $output = <OUTPUT>;
		close(OUTPUT);

		my @entries = split(/\s+/, $output);
		if ($entries[0] =~ /^\//) {
			return $entries[0];
		}
	}
	return undef;
}

=head2 * _packageset

Returns a PackageSet of OpenNMS::Release::Package objects in this repository. This
must be uncached, and implemented by subclasses.

=cut

sub _packageset {
	croak "You must implement this in your subclass!";
}

sub packageset {
	my $self = shift;

	if (not exists $self->{PACKAGESET}) {
		$self->{PACKAGESET} = $self->_packageset;
	}
	return $self->{PACKAGESET};
}

sub _add_to_packageset($) {
	my $self    = shift;
	my $package = shift;

	if (exists $self->{PACKAGESET}) {
		$self->{PACKAGESET}->add($package);
	}
}

=head2 * delete

Delete the repository from the filesystem.

=cut

sub delete {
	my $self = shift;

	rmtree($self->path) or croak "Unable to remove " . $self->path;
	return 1;
}

sub copy_package($$) {
	my $self    = shift;
	my $package = shift;
	my $topath  = shift;

	$self->dirty(1);

	my $newpackage = $package->copy($topath);
	$self->_add_to_packageset($newpackage);
	return $newpackage;
}

sub link_package($$) {
	my $self   = shift;
	my $package    = shift;
	my $topath = shift;

	$self->dirty(1);

	my $newpackage = $package->link($topath);
	$self->_add_to_packageset($newpackage);
	return $newpackage;
}

sub symlink_package($$) {
	my $self   = shift;
	my $package    = shift;
	my $topath = shift;

	$self->dirty(1);

	my $newpackage = $package->symlink($topath);
	$self->_add_to_packageset($newpackage);
	return $newpackage;
}

=head2 * install_package($package, $target_path)

Given an package and a target path relative to the repository path, install
the package into the repository.

For example, C<$repo-E<gt>install_package($package, "opennms/i386")> will install
the package into C<$repo-E<gt>path>/opennms/i386/C<package_filename>.

=cut

sub install_package($$) {
	my $self   = shift;
	my $package    = shift;
	my $topath = shift;

	my $finalpath = File::Spec->catfile($self->abs_path, $topath);
	mkpath($finalpath);
	$self->copy_package($package, $finalpath);
}

=head2 * share_package($source_repo, $package)

Given a source repository and an package object, hard link the package into the
equivalent location in the current repository, if it is newer than the
newest existing version of that package.

=cut

sub share_package($$) {
	my $self      = shift;
	my $from_repo = shift;
	my $package       = shift;

	my $topath_r   = dirname($package->relative_path($from_repo->abs_path));
	my $abs_topath = File::Spec->catfile($self->abs_path, $topath_r);

	my $local_package = $self->find_newest_package_by_name($package->name, $package->arch);

	if (not defined $local_package or $package->is_newer_than($local_package)) {
		$self->link_package($package, $abs_topath);
		return 1;
	}
	return 0;
}

=head2 * share_all_packages($source_repo)

Given a source repository, share any package in that source repository that is
newer than the equivalent package in the current repository.  If no equivalent package
exists, then share the newest package.

=cut

sub share_all_packages($) {
	my $self      = shift;
	my $from_repo = shift;

	my $count = 0;
	for my $package (@{$from_repo->find_newest_packages()}) {
		$count += $self->share_package($from_repo, $package);
	}
	return $count;
}


=head2 * find_all_packages

Locate all Packages in the repository.  Returns a list of
L<OpenNMS::Release::Package> objects.

=cut

sub find_all_packages {
	my $self = shift;

	return $self->packageset->find_all();
}

=head2 * find_newest_packages

Locate the newest version of each package in the repository (based
on the name of the package, not filesystem details).  Returns a list
of L<OpenNMS::Release::Package> objects.

=cut

sub find_newest_packages {
	my $self = shift;
	return $self->packageset->find_newest();
}

=head2 * find_obsolete_packages

Locate all but the newest version of each package in the repository.
Returns a list of L<OpenNMS::Release::Package> objects.

=cut

sub find_obsolete_packages {
	my $self = shift;
	return $self->packageset->find_obsolete();
}

=head2 * find_newest_package_by_name($name, $arch)

Given a package name, returns the newest L<OpenNMS::Release::Package> object
by that name and architecture in the repository.
If no package by that name exists, returns undef.

=cut

sub find_newest_package_by_name {
	my $self      = shift;
	my $name      = shift;
	my $arch      = shift;

	my $newest = $self->packageset->find_newest_by_name($name);
	return undef unless (defined $newest);

	if (not defined $arch) {
		carp "WARNING: No architecture specified. This is probably not what you want.\n";
		return $newest->[0];
	} else {
		for my $package (@$newest) {
			if ($package->arch eq $arch) {
				return $package;
			}
		}
		return undef;
	}
}

=head2 * find_newest_packages_by_name

Given a package name, returns the newest list f L<OpenNMS::Release::Package> objects
for each architecture by that name in the repository.  If no package by that name
exists, returns undef.

=cut

sub find_newest_packages_by_name {
	my $self      = shift;
	my $name      = shift;

	return $self->packageset->find_newest_by_name($name);
}

=head2 * delete_obsolete_packages

Removes all but the newest packages from the repository.

Optionally, takes a subroutine reference.  Each obsolete package
object is passed to this subroutine, along with the repository
object, and if it returns true (1), that package will be deleted.

Examples:

=over 2

=item $repo-E<gt>delete_obsolete_packages(sub { $_[0]-E<gt>name eq "iplike" })

Only delete obsolete packages named "iplike".

=item $repo-E<gt>delete_obsolete_packages(sub { $_[0]-E<gt>path =~ /monkey/ })

Only delete obsolete packages in a filesystem path containing the text "monkey".

=item $repo-E<gt>delete_obsolete_packages(sub { $_[0]-E<gt>version =~ /^1/ })

Only delete obsolete packages whose version starts with 1.

=item $repo-E<gt>delete_obsolete_packages(sub { $_[1]-E<gt>release =~ /unstable/ })

Only delete obsolete packages in the "unstable" repository.

=back

=cut

sub delete_obsolete_packages {
	my $self = shift;
	my $sub  = shift || sub { 1 };

	my $count = 0;
	for my $package (@{$self->find_obsolete_packages}) {
		if ($sub->($package, $self)) {
			$self->dirty(1);
			$package->delete;
			$count++;
		}
	}
	$self->clear_cache();

	return $count;
}

=head2 * index_if_necessary

Create the YUM indexes for this repository, if any
changes have been made.

Takes the same options as the index method.

=cut

sub index_if_necessary($) {
	my $self    = shift;
	my $options = shift;

	if ($self->dirty) {
		$self->index($options);
	} else {
		return 0;
	}

	return 1;
}

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
