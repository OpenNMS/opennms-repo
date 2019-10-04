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

use OpenNMS::Util 2.6.0;

=head1 NAME

OpenNMS::Release::Repo - Perl extension that represents a package repository

=head1 SYNOPSIS

  use OpenNMS::Release::Repo;

=head1 DESCRIPTION

This represents an individual package repository.

=cut

our $VERSION = 2.7.3;

our $DF      = undef;
our $RSYNC   = undef;

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

=over 4

=item * new_with_base($newbase)

Given a new base path, construct a Repo object matching the current,
but with the new base path.

=cut

sub new_with_base($) {
	croak "You must implement 'new_with_base' in your subclass!";
}

=item * base

The base (root) path of this repository.

=cut

sub base {
	my $self = shift;
	return $self->{BASE};
}

# obsolete
sub abs_base {
	return shift->base;
}

=item * path

The full path to the top-level directory of this repository.  (Must be implemented in subclasses.)

=cut

sub path {
	croak "You must implement 'path' in your subclass!";
}

# obsolete
sub abs_path {
	return shift->path;
}

sub _dirty {
	my $self = shift;
	if (@_) { $self->{DIRTY} = shift }
	return $self->{DIRTY};
}

=item * copy($new_base_path)

Given a new base path, copy this repository to the new path using rsync.
Returns an OpenNMS::Release::Repo object, representing this new base path.

If possible, it will create the new repository using hard links.

=cut

sub copy {
	my $self    = shift;
	my $newbase = shift;
	if (not defined $newbase) {
		return undef;
	}

	if (not defined $RSYNC) {
		$RSYNC = find_executable('rsync');
		if (not defined $RSYNC) {
			carp "Unable to locate \`rsync\`: $!";
			return undef;
		}
	}

	my $repo = $self->new_with_base($newbase);
	mkpath($repo->path);

	my $selfpath = $self->path;
	my $repopath = $repo->path;

	my $source_fs = $self->_get_fs_for_path($selfpath);
	my $dest_fs   = $self->_get_fs_for_path($repopath);

	if (defined $source_fs and defined $dest_fs and $source_fs eq $dest_fs) {
		system($RSYNC, "-aqrH", "--no-compress", "--exclude=*.bak", "--link-dest=" . $selfpath . "/", $selfpath . "/", $repopath . "/") == 0 or croak "failure while rsyncing: $!";
	} else {
		system($RSYNC, "-aqrH", "--exclude=*.bak", $selfpath . "/", $repopath . "/") == 0 or croak "failure while rsyncing: $!";
	}

	return $repo;
}

=item * replace($target_repository)

Given a target repository, replace the target repository with the contents of the
current repository.

=cut

sub replace {
	my $self        = shift;
	my $target_repo = shift;

	my $self_path   = $self->path;
	my $target_path = $target_repo->path;
	my $backup_path     = $target_path . '.bak';

	croak "paths match -- this should not be" if ($self_path eq $target_path);

	if (-e $backup_path) {
		carp "stale backup path ($backup_path) found, deleting";
		rmtree($backup_path);
	}

	if (-e $target_path) {
		File::Copy::move($target_path, $backup_path) or croak "failed to rename $target_path to $backup_path: $!";
	}

	mkpath($target_path);
	File::Copy::move($self_path, $target_path) or croak "failed to rename $self_path to $target_path: $!";

	if (-e $backup_path) {
		rmtree($backup_path) or croak "failed to remove old $backup_path directory: $!";
	}

	$self->delete;

	return $self->new_with_base($target_repo->base);
}

=item * create_temporary

Creates a temporary repository that is a copy of the current repository.
This temporary repository is automatically deleted on exit of the calling
program.

=cut

sub create_temporary {
	my $self = shift;

	my $CLEANUP = exists $ENV{OPENNMS_CLEANUP}? $ENV{OPENNMS_CLEANUP} : 1;
	# create a temporary directory at the same level as the current base
	mkpath($self->abs_base);
	my $newbase = tempdir('.temporary-repository-XXXXXX', DIR => $self->abs_base, CLEANUP => $CLEANUP);
	return $self->copy($newbase);
}

sub _get_fs_for_path($) {
	my $self = shift;
	my $path = shift;

	mkpath($path);

	if (not defined $DF) {
		$DF = find_executable('df');
		if (not defined $DF) {
			carp "unable to locate \`df\`: $!";
			return undef;
		}
	}

	if ($? == 0) {
		open(OUTPUT, "$DF -h '$path' |") or croak "unable to run 'df -h $path': $!";
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

=item * _packageset

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

=item * delete

Delete the repository from the filesystem.

=cut

sub delete {
	my $self = shift;

	$self->clear_cache;
	$self->_dirty(1);

	return 1 if (not -e $self->path);

	rmtree($self->path) or croak "Unable to remove " . $self->path;

	# clean up any loose directories which have no files in them
	my @parts;
	my $rel = File::Spec->abs2rel($self->path, $self->base);
	if (defined $rel and $rel ne "") {
		@parts = File::Spec->splitdir($rel);

		while (@parts) {
			my $rm = File::Spec->catdir($self->base, @parts);
			rmdir($rm);
			pop @parts;
		}
		rmdir($self->base);
	}

	return 1;
}

sub _get_final_path($$) {
	my $self    = shift;
	my $topath  = shift;

	my $finalpath = undef;
	return $self->path unless (defined $topath);

	if (File::Spec->file_name_is_absolute($topath)) {
		return $topath;
	} else {
		return File::Spec->catdir($self->path, $topath);
	}
}

sub delete_package($) {
	my $self    = shift;
	my $package = shift;

	my $ret = $self->packageset->remove($package);
	$self->_dirty(1);
	$package->delete;
	return $ret;
}

sub copy_package($$) {
	my $self    = shift;
	my $package = shift;
	my $topath  = shift;

	my $finalpath = $self->_get_final_path($topath);
	mkpath($finalpath);

	my $newpackage = $package->copy($finalpath);
	if (not defined $newpackage) {
		croak "failed to copy " . $package->to_string . " to $finalpath";
	}

	$self->_add_to_packageset($newpackage);
	$self->_dirty(1);

	return $newpackage;
}

sub link_package($$) {
	my $self    = shift;
	my $package = shift;
	my $topath  = shift;

	my $finalpath = $self->_get_final_path($topath);
	mkpath($finalpath);

	my $newpackage = $package->link($finalpath);
	if (not defined $newpackage) {
		croak "failed to link " . $package->to_string . " to $finalpath";
	}

	$self->_add_to_packageset($newpackage);
	$self->_dirty(1);

	return $newpackage;
}

sub symlink_package($$) {
	my $self    = shift;
	my $package = shift;
	my $topath  = shift;

	$self->_dirty(1);

	my $newpackage = $package->symlink($topath);
	if (not defined $newpackage) {
		croak "failed to symlink " . $package->to_string . " to $topath";
	}
	$self->_add_to_packageset($newpackage);
	return $newpackage;
}

=item * install_package($package, $target_path)

Given an package and an optional target path relative to the repository path, install
the package into the repository.

For example, C<$repo-E<gt>install_package($package, "opennms/i386")> will install
the package into C<$repo-E<gt>path>/opennms/i386/C<package_filename>.

=cut

sub install_package($$) {
	my $self    = shift;
	my $package = shift;
	my $topath  = shift;

	$self->copy_package($package, $topath);
}

=item * share_package($source_repo, $package)

Given a source repository and an package object, hard link the package into the
equivalent location in the current repository, if it is newer than the
newest existing version of that package.

=cut

sub share_package($$) {
	my $self      = shift;
	my $from_repo = shift;
	my $package   = shift;

	if (grep { $_ eq $package->name } @{$self->exclude_share}) {
		return 0;
	}

	my $topath_r   = dirname($package->relative_path($from_repo->path));
	my $abs_topath = $topath_r eq '.'? $self->path : File::Spec->catdir($self->path, $topath_r);

	my $local_package = $self->find_newest_package_by_name($package->name, $package->arch);

	if (not defined $local_package or $package->is_newer_than($local_package)) {
		$self->link_package($package, $abs_topath);
		return 1;
	}
	return 0;
}

=item * share_all_packages($source_repo)

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

=item * exclude_share

A (reference to a) list of package names that should be ignored when sharing
asource repository with this one.

=cut

sub exclude_share {
	my $self = shift;

	if (not exists $self->{EXCLUDE_SHARE}) {
		$self->{EXCLUDE_SHARE} = [];

		my $exclude_file = File::Spec->catfile($self->path, '.exclude-share');
		if (-e $exclude_file) {
			for my $name (split(/\s*[\r\n]+\s*/, slurp($exclude_file))) {
				next if ($name =~ /^\s*$/);
				push(@{$self->{EXCLUDE_SHARE}}, $name);
			}
		}
	}

	return $self->{EXCLUDE_SHARE};
}

=item * find_all_packages

Locate all Packages in the repository.  Returns a list of
L<OpenNMS::Release::Package> objects.

=cut

sub find_all_packages {
	my $self = shift;

	return $self->packageset->find_all();
}

=item * find_newest_packages

Locate the newest version of each package in the repository (based
on the name of the package, not filesystem details).  Returns a list
of L<OpenNMS::Release::Package> objects.

=cut

sub find_newest_packages {
	my $self = shift;
	return $self->packageset->find_newest();
}

=item * find_obsolete_packages

Locate all but the newest version of each package in the repository.
Returns a list of L<OpenNMS::Release::Package> objects.

=cut

sub find_obsolete_packages {
	my $self = shift;
	return $self->packageset->find_obsolete();
}

=item * find_newest_package_by_name($name, $arch)

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

=item * find_newest_packages_by_name

Given a package name, returns the newest list f L<OpenNMS::Release::Package> objects
for each architecture by that name in the repository.  If no package by that name
exists, returns undef.

=cut

sub find_newest_packages_by_name {
	my $self      = shift;
	my $name      = shift;

	return $self->packageset->find_newest_by_name($name);
}

=item * delete_obsolete_packages([\&subroutine])

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
			$self->delete_package($package);
			$count++;
		}
	}
	#$self->clear_cache();

	return $count;
}

=item * sign_all_packages($signing_id, $signing_password, [\&sign], [\&status])

Given a GPG id and password, (re-)sign all the packages in the repository.

Takes 2 optional subroutines.

The first, like delete_obsolete_packages, will receive as arguments the package object,
and the repository object. If it returns 1, that package will be signed.

The second receives as arguments the package, the current count, the total count
of packages to be processed, and whether or not the package was chosen to be signed
by the &sign method.

=cut

sub sign_all_packages {
	my $self             = shift;
	my $signing_id       = shift;
	my $signing_password = shift;
	my $sign_method      = shift || sub { 1 };
	my $status_method    = shift || sub {};

	my $count = 0;
	my @all_packages = @{$self->find_all_packages};
	my $total = scalar(@all_packages);
	for my $package (@all_packages) {
		my $should_sign = $sign_method->($package, $self);
		if ($should_sign) {
			$package->sign($signing_id, $signing_password) or croak "Failed to sign " . $package->to_string;
			$self->_dirty(1);
		}
		$count++;
		$status_method->($package, $count, $total, $should_sign);
	}

	return 1;
}

=item * index_if_necessary

Create the YUM indexes for this repository, if any
changes have been made.

Takes the same options as the index method.

=cut

sub index_if_necessary($) {
	my $self    = shift;
	my $options = shift;

	if ($self->_dirty) {
		$self->index($options);
	} else {
		return 0;
	}

	return 1;
}

=item * begin

Begin a transaction.  Commit changes using commit(), otherwise, abort().

Returns the repository object to be manipulated inside the transaction.

=cut

sub begin() {
	my $self = shift;

	if (exists $self->{ORIGINAL_REPO}) {
		croak "tried to start a transation on an object that's already in a transaction! (original repo = " . $self->to_string . ")";
	}

	my $temporary = $self->create_temporary;
	$temporary->{ORIGINAL_REPO} = $self;
	return $temporary;
}

=item * commit

Called on the temporary object from begin(), commits the changes that have occurred
since the start of the transaction.

Returns the committed repository object.

=cut

sub commit($) {
	my $self    = shift;
	my $options = shift;

	# first, index the changes
	my $index = $self->index_if_necessary($options);

	# reset the original object
	my $original = delete $self->{ORIGINAL_REPO};
	$original->clear_cache;
	$original->_dirty(0);

	# copy ourselves over the original
	my $new = $self->copy($original->base);

	my $delete = $self->delete;
	carp "error while deleting " . $self->to_string unless ($delete);

	return $new;
}

=item * abort

Called on the temporary object from begin(), aborts the changes that have occurred
since the start of the transaction.

Returns the original, unmodified repository object.

=cut

sub abort() {
	my $self = shift;

	my $original = delete $self->{ORIGINAL_REPO};
	$self->delete;

	return $original;
}


=head2 * to_string

A convenient way of displaying the repository.

=cut

sub to_string() {
	my $self = shift;
	return $self->path;
}

1;

__END__
=back

=head1 AUTHOR

Benjamin Reed E<lt>ranger@opennms.orgE<gt>
Matt Brozowski E<lt>brozow@opennms.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by The OpenNMS Group, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
