package OpenNMS::Release::Repo;

use 5.008008;
use strict;
use warnings;

use Carp;
use Cwd qw();
use Data::Dumper;
use File::Path;
use File::Basename;
use File::Temp qw(tempdir);

=head1 NAME

OpenNMS::Release::Repo - Perl extension that represents a package repository

=head1 SYNOPSIS

  use OpenNMS::Release::Repo;

=head1 DESCRIPTION

This represents an individual package repository.

=cut

our $VERSION = '2.1';

=head1 CONSTRUCTOR

OpenNMS::Release::Repo-E<gt>new($base);

Create a new Repo object, based in path $base.  You can add and remove packages to/from it, re-index it, and so on.
The base will always be initialized as the absolute path.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};

	my $base = shift;
	if (not defined $base or not File::Spec->file_name_is_absolute( $base )) {
		croak "base must be an absolute path!";
	}

	$base =~ s,/$,,;
	$self->{BASE} = $base;
	$self->{DIRTY} = 0;

	bless($self);
	return $self;
}


=head1 METHODS

=head2 * new_with_base($newbase)

Given a new base path, construct a Repo object matching the current,
but with the new base path.

=cut

sub new_with_base($) {
	croak "You must implement 'new_with_base' in your subclass!";
}

sub base {
	my $self = shift;
	return $self->{BASE};
}

sub abs_base {
	return shift->base;
}

sub path {
	croak "You must implement 'path' in your subclass!";
}

sub abs_path {
	return shift->path;
}

sub dirty {
	my $self = shift;
	if (@_) { $self->{DIRTY} = shift }
	return $self->{DIRTY};
}

=head2 * copy

Given a new base path, copy this repository to the new path using rsync.
Returns an OpenNMS::Release::Repo object, representing this new base path.

If possible, it will create the new repository using hard links.

=cut

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

	my $repo = $self->new_with_base($newbase);
	mkpath($repo->path);

	my $selfpath = $self->path;
	my $repopath = $repo->path;

	my $source_fs = $self->_get_fs_for_path($selfpath);
	my $dest_fs   = $self->_get_fs_for_path($repopath);

	if (defined $source_fs and defined $dest_fs and $source_fs eq $dest_fs) {
		system($rsync, "-aqrH", "--link-dest=" . $selfpath . "/", $selfpath . "/", $repopath . "/") == 0 or croak "failure while rsyncing: $!";
	} else {
		system($rsync, "-aqrH", $selfpath . "/", $repopath . "/") == 0 or croak "failure while rsyncing: $!";
	}

	return $repo;
}

=head2 * replace

Given a target repository, replace the target repository with the contents of the
current repository.

=cut

sub replace {
	my $self        = shift;
	my $target_repo = shift;

	croak "releases do not match! (" . $self->release . " != " . $target_repo->release . ")" if ($self->release ne $target_repo->release);

	my $self_path   = $self->path;
	my $target_path = $target_repo->path;

	croak "paths match -- this should not be" if ($self_path eq $target_path);

	File::Copy::move($target_path, $target_path . '.bak') or croak "failed to rename $target_path to $target_path.bak: $!";
	File::Copy::move($self_path, $target_path) or croak "failed to rename $self_path to $target_path: $!";

	rmtree($target_path . '.bak') or croak "failed to remove old $target_path.bak directory: $!";

	rmdir($self->releasedir);
	rmdir($self->base);

	return $self->new_with_base($target_repo->base);
}

=head2 * create_temporary

Creates a temporary repository that is a copy of the current repository.
This temporary repository is automatically deleted on exit of the calling
program.

=cut

sub create_temporary {
	my $self = shift;

	my $CLEANUP = exists $ENV{OPENNMS_CLEANUP}? $ENV{OPENNMS_CLEANUP} : 1;
	# create a temporary directory at the same level as the current base
	my $newbase = tempdir('.repoXXXXXX', DIR => $self->abs_base, CLEANUP => $CLEANUP);
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

sub clear_cache() {
	my $self = shift;
	return delete $self->{PACKAGESET};
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
	if (not defined $newpackage) {
		croak "failed to copy " . $package->to_string . " to $topath";
	}
	$self->_add_to_packageset($newpackage);

	return $newpackage;
}

sub link_package($$) {
	my $self    = shift;
	my $package = shift;
	my $topath  = shift;

	$self->dirty(1);

	my $newpackage = $package->link($topath);
	if (not defined $newpackage) {
		croak "failed to link " . $package->to_string . " to $topath";
	}
	$self->_add_to_packageset($newpackage);
	return $newpackage;
}

sub symlink_package($$) {
	my $self    = shift;
	my $package = shift;
	my $topath  = shift;

	$self->dirty(1);

	my $newpackage = $package->symlink($topath);
	if (not defined $newpackage) {
		croak "failed to symlink " . $package->to_string . " to $topath";
	}
	$self->_add_to_packageset($newpackage);
	return $newpackage;
}

=head2 * install_package($package, $target_path)

Given an package and an optional target path relative to the repository path, install
the package into the repository.

For example, C<$repo-E<gt>install_package($package, "opennms/i386")> will install
the package into C<$repo-E<gt>path>/opennms/i386/C<package_filename>.

=cut

sub install_package($$) {
	my $self    = shift;
	my $package = shift;
	my $topath  = shift;

	my $finalpath = defined $topath? File::Spec->catfile($self->path, $topath) : $self->path;
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
	my $package   = shift;

	my $topath_r   = dirname($package->relative_path($from_repo->path));
	my $abs_topath = File::Spec->catfile($self->path, $topath_r);

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

sub begin() {
	my $self = shift;

	if (exists $self->{ORIGINAL_REPO}) {
		croak "tried to start a transation on an object that's already in a transaction! (original repo = " . $self->to_string . ")";
	}

	my $temporary = $self->create_temporary;
	$temporary->{ORIGINAL_REPO} = $self;
	return $temporary;
}

sub commit($) {
	my $self    = shift;
	my $options = shift;

	# first, index the changes
	my $index = $self->index_if_necessary($options);

	# reset the original object
	my $original = delete $self->{ORIGINAL_REPO};
	$original->clear_cache;
	$original->dirty(0);

	# copy ourselves over the original
	my $new = $self->copy($original->base);

	my $delete = $self->delete;
	carp "error while deleting " . $self->to_string unless ($delete);

	return $new;
}

sub abort() {
	my $self = shift;

	my $original = delete $self->{ORIGINAL_REPO};
	$self->delete;

	return $original;
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
