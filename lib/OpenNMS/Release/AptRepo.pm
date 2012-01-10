package OpenNMS::Release::AptRepo;

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
use OpenNMS::Release::DebPackage;
use OpenNMS::Release::PackageSet;

use base qw(OpenNMS::Release::Repo);

=head1 NAME

OpenNMS::Release::AptRepo - Perl extension that represents a Debian APT repository

=head1 SYNOPSIS

  use OpenNMS::Release::AptRepo;

=head1 DESCRIPTION

This represents an individual Debian APT repository, i.e., a directory in which
you would run "apt-ftparchive".

Repositories are expected to be in the form:

  C<base>/dists/C<release>

=cut

our $VERSION = '2.1';
our $APT_FTPARCHIVE = undef;
our @ARCHITECTURES = qw(amd64 i386 powerpc);

=head1 CONSTRUCTOR

OpenNMS::Release::AptRepo-E<gt>new($base, $release);

Create a new Repo object.  You can add and remove packages to/from it, re-index it, and so on.

=over 2

=item base - the top-level path for the repository

=item release - the name of the release, e.g., "nightly-1.8", "opennms-1.9", etc.

=back

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $base      = shift;
	my $release   = shift;

	my $self = bless($proto->SUPER::new($base), $class);

	if (not defined $release) {
		carp "You did not specify a release!";
		return undef;
	}

	if (not defined $APT_FTPARCHIVE) {
		my $apt_ftparchive = `which apt-ftparchive 2>/dev/null`;
		if ($? != 0) {
			croak "Unable to locate \`apt-ftparchive\` executable!";
		}
		chomp($apt_ftparchive);
		$APT_FTPARCHIVE=$apt_ftparchive;
	}

	$self->{RELEASE}  = $release;

	return $self;
}

sub new_with_base($) {
	my $self = shift;
	my $base = shift;

	return OpenNMS::Release::AptRepo->new($base, $self->release);
}

=head1 METHODS

=head2 * find_repos($base)

Search for repositories, given a base path.  Returns a list
of OpenNMS::Release::AptRepo objects representing the repositories found.

=cut

sub find_repos($) {
	my $class = shift;
	my $base = shift;

	my @repos;
	my @repodirs;

	find({ wanted => sub {
		if (-f $File::Find::name and $File::Find::name =~ /dists\/[^\/]+\/Release$/) {
			push(@repodirs, dirname($File::Find::name));
		}
	}, no_chdir => 1 }, $base);

	for my $repodir (@repodirs) {
		$repodir = File::Spec->abs2rel($repodir, $base);
		my @parts = File::Spec->splitdir($repodir);
		if (scalar(@parts) != 3) {
			carp "not sure how to determine release and platform for $base/$repodir";
			next;
		}
		push(@repos, OpenNMS::Release::DebRepo->new($base, $parts[1]));
	}
	@repos = sort { $a->path cmp $b->path } @repos;
	return \@repos;
}

=head2 * release

The 'release' of the repository, e.g., "opennms-1.8", "nightly-1.9", etc.
This is expected to be a subdirectory under the C<base>/dists directory.

=cut

sub release {
	my $self = shift;
	return $self->{RELEASE};
}

=head2 * path

The path of the repository (base + release).

=cut

sub path() {
	my $self = shift;
	return File::Spec->catfile($self->base, 'dists', $self->release);
}

=head2 * releasedir

The path of the release directory (base + release).

=cut

sub releasedir() {
	my $self = shift;
	return File::Spec->catfile($self->base, 'dists', $self->release);
}

=head2 * to_string

A convenient way of displaying the repository.

=cut

sub to_string() {
	my $self = shift;
	return $self->path;
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
		return unless ($File::Find::name =~ /\.deb$/);
		return unless (-e $File::Find::name);
		my $package = OpenNMS::Release::DebPackage->new($File::Find::name);
		push(@packages, $package);
	}, no_chdir => 1}, $self->path);
	return OpenNMS::Release::PackageSet->new(\@packages);
	
}

sub install_package {
	my $self    = shift;
	my $package = shift;
	my $topath  = File::Spec->catfile($self->path, 'main', 'binary-' . $package->arch);

	mkpath($topath);
	$self->copy_package($package, $topath);
}

sub cachedir() {
	my $self = shift;
	return File::Spec->catfile($self->base, "ftparchive");
}

=head2 * index({options})

Create the APT indexes for this repository.

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
	for my $arch (@ARCHITECTURES) {
		mkpath(File::Spec->catfile($self->path, 'main', 'binary-' . $arch));
	}
	mkpath(File::Spec->catfile($self->path, 'main', 'source'));

	my $release_handle = IO::Handle->new();
	my $path           = $self->path;
	my $indexfile      = $self->indexfile;
	system($APT_FTPARCHIVE, 'generate', $indexfile) == 0 or croak "unable to run $APT_FTPARCHIVE generate: $!";

	open($release_handle, "$APT_FTPARCHIVE -c '$indexfile' release $path |") == 0 or croak "unable to run $APT_FTPARCHIVE release: $!";
	my $release_contents = "";
	{
		local $/ = undef;
		$release_contents = <$release_handle>;
	}
	close($release_handle);

	my $output_handle = IO::Handle->new();
	my $output_filename = File::Spec->catfile($path, 'Release');
	open($output_handle, '>' . $output_filename) or croak "unable to write to $output_filename: $!";
	print $output_handle $release_contents;
	close($output_handle);

#	my $id       = $options->{'signing_id'};
#	my $password = $options->{'signing_password'};
#
#	if (defined $id and defined $password) {
#		my $repodata = File::Spec->catfile($self->path, 'repodata');
#		gpg_write_key($id, $password, File::Spec->catfile($repodata, 'repomd.xml.key'));
#		gpg_detach_sign_file($id, $password, File::Spec->catfile($repodata, 'repomd.xml'));
#	}

	$self->dirty(0);
	return 1;
}

sub indexfile() {
	my $self = shift;
	return File::Spec->catfile($self->base, $self->release . '.conf');
}

sub create_indexfile() {
	my $self = shift;

	my $outputfile = IO::Handle->new();
	my $filename = $self->indexfile();
	open ($outputfile, '>' . $filename) or croak "Unable to write to $filename: $!";

	my $archivedir = $self->base;
	my $cachedir   = $self->cachedir;
	my $release    = $self->release;
	my $arches     = join(' ', @ARCHITECTURES);

	print $outputfile <<END;
Dir {
        ArchiveDir "$archivedir";
        CacheDir "$cachedir";
};

Default {
        Packages::Compress ". bzip2 gzip";
        Sources::Compress ". bzip2 gzip";
        Contents::Compress ". bzip2 gzip";
};

APT::FTPArchive {
        Release {
                Origin "OpenNMS";
                Label "OpenNMS Repository: $release";
                Suite "$release";
                Codename "$release";
                Architectures "$arches source";
                Sections "main";
                Description "OpenNMS Repository: $release";
        };

	close($outputfile);
};

Tree "dists/$release" {
        Sections "main";
        Architectures "$arches source";
};
END

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
