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
	@repos = sort { $a->path cmp $b->path } @repos;
	return \@repos;
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

=head2 * delete

Delete the repository from the filesystem.

=cut

sub delete {
	my $self = shift;
	$self->SUPER::delete(@_);

	rmdir($self->releasedir);
	rmdir($self->base);
	return 1;
}

sub _packageset {
	my $self = shift;

	my @packages = ();
	find({ wanted => sub {
		return unless ($File::Find::name =~ /\.rpm$/);
		return unless (-e $File::Find::name);
		my $package = OpenNMS::Release::RPMPackage->new($File::Find::name);
		push(@packages, $package);
	}, no_chdir => 1}, $self->path);
	return OpenNMS::Release::PackageSet->new(\@packages);
	
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