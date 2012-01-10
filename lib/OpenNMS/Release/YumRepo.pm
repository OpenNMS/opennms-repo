package OpenNMS::Release::YumRepo;

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
use OpenNMS::Release::RPMPackage;
use OpenNMS::Release::PackageSet;

use base qw(OpenNMS::Release::Repo);

=head1 NAME

OpenNMS::Release::YumRepo - Perl extension that represents a YUM repository

=head1 SYNOPSIS

  use OpenNMS::Release::YumRepo;

=head1 DESCRIPTION

This represents an individual YUM repository, i.e., a directory in which
you would run "createrepo".

Repositories are expected to be in the form:

  C<base>/C<platform>/C<repository>

They may optionally have subdirectories under the repository, which will
be preserved when sharing RPMs between repositories.

=cut

our $VERSION = '2.0';
our $CREATEREPO = undef;
our $CREATEREPO_USE_CHECKSUM = 0;

=head1 CONSTRUCTOR

OpenNMS::Yum::Repo-E<gt>new($base, $release, $platform);

Create a new Repo object.  You can add and remove RPMs to/from it, re-index it, and so on.

=over 2

=item base - the top-level path for the repository

=item release - the name of the release, e.g., "snapshot", "testing", etc.

=item platform - the platform for the release, e.g., "rhel5", "common", etc.

=back

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = bless($proto->SUPER::new(@_), $class);

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

	if (not defined $CREATEREPO) {
		my $createrepo = `which createrepo 2>/dev/null`;
		if ($? != 0) {
			croak "Unable to locate \`createrepo\` executable!";
		}
		chomp($createrepo);
		$CREATEREPO=$createrepo;


		my $handle = IO::Handle->new();
		open($handle, "$CREATEREPO --help 2>&1 |") or croak "unable to run $CREATEREPO: $!";
		while (<$handle>) {
			if (/--checksum=SUMTYPE/) {
				$CREATEREPO_USE_CHECKSUM = 1;
				last;
			}
		}
		close($handle);
	}

	$base =~ s/\/$//;

	$self->{DIRTY}    = 0;
	$self->{BASE}     = $base;
	$self->{RELEASE}  = $release;
	$self->{PLATFORM} = $platform;

	return $self;
}

=head1 METHODS

=head2 * find_repos($base)

Search for repositories, given a base path.  Returns a list
of OpenNMS::Release::YumRepo objects representing the repositories found.

=cut

sub find_repos($) {
	my $class = shift;
	my $base = shift;

	my @repos;
	my @repodirs;

	find({ wanted => sub {
		if (-d $File::Find::name and $File::Find::name =~ /\/repodata$/) {
			push(@repodirs, dirname($File::Find::name));
		}
	}, no_chdir => 1 }, $base);

	for my $repodir (@repodirs) {
		$repodir = File::Spec->abs2rel($repodir, $base);
		my @parts = File::Spec->splitdir($repodir);
		if (scalar(@parts) != 2) {
			carp "not sure how to determine release and platform for $base/$repodir";
			next;
		}
		push(@repos, OpenNMS::Release::YumRepo->new($base, $parts[0], $parts[1]));
	}
	return \@repos;
}

sub dirty {
	my $self = shift;
	if (@_) { $self->{DIRTY} = shift }
	return $self->{DIRTY};
}

sub clear_cache() {
	my $self = shift;
	return delete $self->{PACKAGESET};
}

=head2 * base

The 'base' of the repository, i.e., the top-level root path the
repository lives in, e.g., /opt/yum.

=cut

sub base {
	my $self = shift;
	return $self->{BASE};
}

=head2 * abs_base

The 'base' of the repository, as an absolute path.

=cut

sub abs_base() {
	my $self = shift;
	return Cwd::abs_path($self->base);
}

=head2 * release

The 'release' of the repository, e.g., "stable", "testing", etc.
This is expected to be a subdirectory immediately under the base directory.

=cut

sub release {
	my $self = shift;
	return $self->{RELEASE};
}

=head2 * platform

The 'platform' or OS of the repository, e.g., "rhel5", "fc15", "common".
This is expected to be a subdirectory immediately under the release directory.

=cut

sub platform {
	my $self = shift;
	return $self->{PLATFORM};
}

=head2 * path

The path of the repository (base + release + platform).

=cut

sub path() {
	my $self = shift;
	return File::Spec->catfile($self->base, $self->release, $self->platform);
}

=head2 * abs_path

The path of the repository, as an absolute path.

=cut

sub abs_path() {
	my $self = shift;
	return Cwd::abs_path($self->path);
}

=head2 * releasedir

The path of the release directory (base + release).

=cut

sub releasedir() {
	my $self = shift;
	return File::Spec->catfile($self->base, $self->release);
}

=head2 * to_string

A convenient way of displaying the repository.

=cut

sub to_string() {
	my $self = shift;
	return $self->path;
}

=head2 * copy

Given a new base path, copy this repository to the new path using rsync.
Returns an OpenNMS::Release::YumRepo object, representing this new base path.

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

	my $repo = OpenNMS::Release::YumRepo->new($newbase, $self->release, $self->platform);
	mkpath($repo->path);

	my $selfpath = $self->abs_path;
	my $repopath = $repo->abs_path;

	my $source_fs = $self->_get_fs_for_path($selfpath);
	my $dest_fs   = $self->_get_fs_for_path($repopath);

	if (defined $source_fs and defined $dest_fs and $source_fs eq $dest_fs) {
		system($rsync, "-aqrH", "--link-dest=" . $selfpath . "/", $selfpath . "/", $repopath . "/") == 0 or croak "failure while rsyncing: $!";
	} else {
		system($rsync, "-aqrH", $selfpath . "/", $repopath . "/") == 0 or croak "failure while rsyncing: $!";
	}

	return $repo;
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

=head2 * replace

Given a target repository, replace the target repository with the contents of the
current repository.

=cut

sub replace {
	my $self        = shift;
	my $target_repo = shift;

	croak "releases do not match! (" . $self->release . " != " . $target_repo->release . ")" if ($self->release ne $target_repo->release);
	croak "platforms do not match! (" . $self->platform . " != " . $target_repo->platform . ")" if ($self->platform ne $target_repo->platform);

	my $self_path   = $self->abs_path;
	my $target_path = $target_repo->abs_path;

	croak "paths match -- this should not be" if ($self_path eq $target_path);

	File::Copy::move($target_path, $target_path . '.bak') or croak "failed to rename $target_path to $target_path.bak: $!";
	File::Copy::move($self_path, $target_path) or croak "failed to rename $self_path to $target_path: $!";

	rmtree($target_path . '.bak') or croak "failed to remove old $target_path.bak directory: $!";

	rmdir($self->releasedir);
	rmdir($self->base);

	return OpenNMS::Release::YumRepo->new($target_repo->abs_base, $self->release, $self->platform);
}

sub _get_fs_for_path($) {
	my $self = shift;
	my $path = shift;

	my $df = `which df 2>/dev/null`;
	if ($? == 0) {
		chomp($df);
		open(OUTPUT, "df -h '$path' |") or croak "unable to run 'df -h $path': $!";
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

=head2 * delete

Delete the repository from the filesystem.

=cut

sub delete {
	my $self = shift;

	rmtree($self->path) or croak "Unable to remove " . $self->path;
	rmdir($self->releasedir);
	rmdir($self->base);
	return 1;
}

sub _packageset {
	my $self = shift;

	if (not exists $self->{PACKAGESET}) {
		my $packages = [];
		find({ wanted => sub {
			return unless ($File::Find::name =~ /\.rpm$/);
			return unless (-e $File::Find::name);
			my $package = OpenNMS::Release::RPMPackage->new($File::Find::name);
			push(@{$packages}, $package);
		}, no_chdir => 1}, $self->path);
		$self->{PACKAGESET} = OpenNMS::Release::PackageSet->new($packages);
	}
	return $self->{PACKAGESET};
	
}

sub _add_to_packageset($) {
	my $self    = shift;
	my $package = shift;

	if (exists $self->{PACKAGESET}) {
		$self->_packageset->add($package);
	}
}

=head2 * find_all_packages

Locate all Packages in the repository.  Returns a list of
L<OpenNMS::Release::Package> objects.

=cut

sub find_all_packages {
	my $self = shift;

	return $self->_packageset->find_all();
}

=head2 * find_newest_packages

Locate the newest version of each package in the repository (based
on the name of the package, not filesystem details).  Returns a list
of L<OpenNMS::Release::Package> objects.

=cut

sub find_newest_packages {
	my $self = shift;
	return $self->_packageset->find_newest();
}

=head2 * find_obsolete_packages

Locate all but the newest version of each package in the repository.
Returns a list of L<OpenNMS::Release::Package> objects.

=cut

sub find_obsolete_packages {
	my $self = shift;
	return $self->_packageset->find_obsolete();
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

	my $newest = $self->_packageset->find_newest_by_name($name);
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

	return $self->_packageset->find_newest_by_name($name);
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

sub copy_package($$) {
	my $self   = shift;
	my $package    = shift;
	my $topath = shift;

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

sub cachedir() {
	my $self = shift;
	return File::Spec->catfile($self->abs_base, "caches", $self->release, $self->platform);
}

=head2 * index({options})

Create the YUM indexes for this repository.

Takes as argument a hash reference containing optional configuration.

Supported options:

=over 2

=item * signing_id - the GPG ID to sign the repository index as.

=item * signing_password - the GPG password to sign the repository index with.

=back

If either of the signing options are not passed, we do not sign the repository.

=cut

sub index($) {
	my $self    = shift;
	my $options = shift;

	mkpath($self->cachedir);
	my @args = ('-q',
		'--outputdir', $self->abs_path,
		'--cachedir', $self->cachedir,
		$self->abs_path);

	if ($CREATEREPO_USE_CHECKSUM) {
		unshift(@args, '--checksum', 'sha');
	}

	system($CREATEREPO, @args) == 0 or croak "createrepo failed! $!";

	my $id       = $options->{'signing_id'};
	my $password = $options->{'signing_password'};

	if (defined $id and defined $password) {
		my $repodata = File::Spec->catfile($self->abs_path, 'repodata');
		gpg_write_key($id, $password, File::Spec->catfile($repodata, 'repomd.xml.key'));
		gpg_detach_sign_file($id, $password, File::Spec->catfile($repodata, 'repomd.xml'));
	}

	$self->dirty(0);
	return 1;
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
