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

use OpenNMS::Util 2.5.0;
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

our $VERSION = 2.10.0;
our $CREATEREPO = undef;
our $CREATEREPO_USE_CHECKSUM = 0;
our $CREATEREPO_USE_DELTAS = 0;
our $CREATEREPO_USE_UPDATE = 0;
our $CREATEREPO_USE_GLOBAL_CACHE = undef;

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

	my $base     = shift;
	my $release  = shift;
	my $platform = shift;

	my $self = bless($proto->SUPER::new($base), $class);

	if (not defined $release) {
		carp "You did not specify a release!";
		return;
	}
	if (not defined $platform) {
		carp "You did not specify a platform!";
		return;
	}

	if (not defined $CREATEREPO) {
		$CREATEREPO = find_executable('createrepo');
		if (not defined $CREATEREPO) {
			croak "Unable to locate \`createrepo\` executable: $!";
		}

		my $handle = IO::Handle->new();
		open($handle, "-|", "$CREATEREPO --help 2>&1") or croak "unable to run $CREATEREPO: $!";
		while (<$handle>) {
			if (/--checksum=SUMTYPE/) {
				$CREATEREPO_USE_CHECKSUM = 1;
			}
			#if (/--deltas/) {
			#	$CREATEREPO_USE_DELTAS = 1;
			#}
			#if (/--update/) {
			#	$CREATEREPO_USE_UPDATE = 1;
			#}
		}
		close($handle);
	}

	$self->{RELEASE}  = $release;
	$self->{PLATFORM} = $platform;

	return $self;
}

sub new_with_base {
	my $self = shift;
	my $base = shift;

	return OpenNMS::Release::YumRepo->new($base, $self->release, $self->platform);
}

=head1 METHODS

=head2 * find_repos($base)

Search for repositories, given a base path.  Returns a list
of OpenNMS::Release::YumRepo objects representing the repositories found.

=cut

sub find_repos {
	my $class = shift;
	my $base = shift;

	my @repos;
	my @repodirs;

	find({ wanted => sub {
		if (-d $File::Find::name and $File::Find::name =~ /\/repodata$/) {
			push(@repodirs, dirname($File::Find::name));
		}
	}, no_chdir => 1, follow_fast => 1, follow_skip => 2 }, $base);

	for my $repodir (@repodirs) {
		if (-l $repodir) {
			carp "$repodir is a symlink... skipping.";
			next;
		}
		$repodir = File::Spec->abs2rel($repodir, $base);
		my @parts = File::Spec->splitdir($repodir);
		if ($parts[0] eq 'branches' and scalar(@parts) == 3) {
			push(@repos, OpenNMS::Release::YumRepo->new(File::Spec->catdir($base, 'branches'), $parts[1], $parts[2]));
			next;
		}
		if (scalar(@parts) != 2) {
			carp "not sure how to determine release and platform for base '$base', repo '$repodir'.";
			next;
		}
		push(@repos, OpenNMS::Release::YumRepo->new($base, $parts[0], $parts[1]));
	}
	@repos = sort { $a->path cmp $b->path } @repos;
	return \@repos;
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

sub path {
	my $self = shift;
	return File::Spec->catdir($self->base, $self->release, $self->platform);
}

=head2 * releasedir

The path of the release directory (base + release).

=cut

sub releasedir {
	my $self = shift;
	return File::Spec->catdir($self->base, $self->release);
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

=head2 * replace

Given a target repository, replace the target repository with the contents of the
current repository.

=cut

sub replace {
	my $self           = shift;
	my $target_repo    = shift;
	my $ignore_release = shift || 0;

	if (not $ignore_release) {
		croak "releases do not match! (" . $self->release . " != " . $target_repo->release . ")" if ($self->release ne $target_repo->release);
	}
	croak "platforms do not match! (" . $self->platform . " != " . $target_repo->platform . ")" if ($self->platform ne $target_repo->platform);

	return $self->SUPER::replace($target_repo);
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

sub cachedir {
	my $self = shift;
	return File::Spec->catdir($self->base, "caches", $self->release, $self->platform);
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

sub index {
	my $self    = shift;
	my $options = shift;

	mkpath($self->cachedir);
	my @args = ('-q',
		'--no-database',
		'--outputdir', $self->path,
		$self->path);

	if ($CREATEREPO_USE_GLOBAL_CACHE) {
		unshift(@args, '--cachedir', $CREATEREPO_USE_GLOBAL_CACHE);
	} else {
		unshift(@args, '--cachedir', $self->cachedir);
	}

	if ($CREATEREPO_USE_UPDATE) {
		unshift(@args, '--update');
	}

	if ($CREATEREPO_USE_CHECKSUM) {
		unshift(@args, '--checksum', 'sha');
	}

	if ($CREATEREPO_USE_DELTAS) {
		my $basedir = $self->base;
		if ($basedir =~ /^(.*)\/branches$/) {
			$basedir = $1;
		}
		unshift(@args, '--deltas', '--num-deltas', '5', '--max-delta-rpm-size', '1000000000');

		my @packages = @{$self->find_all_packages()};

		my $stabledir = File::Spec->catdir($basedir, 'stable', $self->platform);
		if (-d $stabledir) {
			my $stable = OpenNMS::Release::YumRepo->new($basedir, 'stable', $self->platform);
			push(@packages, @{$stable->find_all_packages()});
		}

		my $oldstabledir = File::Spec->catdir($basedir, 'oldstable', $self->platform);
		if (-d $oldstabledir) {
			my $oldstable = OpenNMS::Release::YumRepo->new($basedir, 'oldstable', $self->platform);
			push(@packages, @{$oldstable->find_all_packages()});
		}

		my $dirs;
		for my $package (@packages) {
			my $path = dirname($package->path);
			$dirs->{$path}++;
		}
		for my $dir (keys %$dirs) {
			unshift(@args, '--oldpackagedirs', $dir);
		}
	}

	system($CREATEREPO, @args) == 0 or croak "createrepo failed! $!";

	my $id       = $options->{'signing_id'};
	my $password = $options->{'signing_password'};

	if (defined $id and defined $password) {
		my $repodata = File::Spec->catdir($self->path, 'repodata');
		gpg_write_key($id, $password, File::Spec->catfile($repodata, 'repomd.xml.key'));
		gpg_detach_sign_file($id, $password, File::Spec->catfile($repodata, 'repomd.xml'));
	}

	$self->_dirty(0);
	return 1;
}

=head2 * enable_deltas(true/false)

Whether or not deltas should be enabled when running createrepo.

Takes a true/false value.

=cut

sub enable_deltas {
	my $self    = shift;
	$CREATEREPO_USE_DELTAS = shift;
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
