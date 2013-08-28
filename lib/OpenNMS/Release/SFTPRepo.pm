package OpenNMS::Release::SFTPRepo;

use 5.008008;
use strict;
use warnings;

use Carp;
use Cwd;
use Data::Dumper;
use Fcntl qw(S_ISDIR);
use File::Basename;
use File::Copy qw();
use File::Find;
use File::Path;
use File::Spec;
use File::Temp qw(tempdir);
use IO::Handle;
use Net::SFTP::Foreign;

use OpenNMS::Util;
use OpenNMS::Release::FilePackage 2.6.3;
use OpenNMS::Release::PackageSet;

use base qw(OpenNMS::Release::Repo);

=head1 NAME

OpenNMS::Release::SFTPRepo - Perl extension that represents a remote SFTP repository

=head1 SYNOPSIS

  use OpenNMS::Release::SFTPRepo;

=head1 DESCRIPTION

This represents a remote SFTP file repository.

=cut

our $VERSION = '2.6.3';

=head1 CONSTRUCTOR

OpenNMS::Release::SFTPRepo-E<gt>new($host, $base, { args => option });

Create a new Repo object.  You can add and remove files to/from it, re-index it, and so on.

=over 2

=item host - the hostname to connect to

=item base - the top-level path for the repository

=item args - a reference to a hash containing additional arguments to pass to Net::SFTP::Foreign.

=back

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $host  = shift;
	my $base  = shift;
	my $args  = shift;

	my $self  = bless($proto->SUPER::new($base), $class);

	$self->{HOST} = $host;
	$self->{IN_TRANSACTION} = 0;
	$self->_init($args);

	return $self;
}

sub new_with_base($) {
	my $self = shift;
	my $base = shift;

	return $self->new($self->host, $base);
}

sub _init {
	my $self = shift;
	my $args = shift;
	$self->{SFTP} = Net::SFTP::Foreign->new($self->host, %$args);
	$self->packageset;
	return 1;
}

=head1 METHODS

=cut

=head2 * path

The path of the repository.

=cut

sub path() {
	my $self = shift;
	return $self->base;
}

=head2 * host

The host to connect to.

=cut

sub host() {
	my $self = shift;
	return $self->{HOST};
}

=head2 * to_string

A convenient way of displaying the repository.

=cut

sub to_string() {
	my $self = shift;
	return 'sftp://' . $self->host . '/' . $self->path;
}

sub _sftp {
	return shift->{SFTP};
}

sub _in_transaction {
	my $self = shift;
	if (@_) { $self->{IN_TRANSACTION} = shift; }
	return $self->{IN_TRANSACTION};
}

sub _packageset {
	my $self = shift;

	my @packages = ();

	my $files = $self->_sftp->ls(
		$self->path,
		wanted => sub {
			my $entry = $_[1];
			return not S_ISDIR($entry->{a}->perm);
		},
		names_only => 1
	);
	for my $file (@{$files}) {
		push(@packages, OpenNMS::Release::FilePackage->new(File::Spec->catfile($self->path, $file)));
	}
	return OpenNMS::Release::PackageSet->new(\@packages);
	
}

sub copy {
	croak "copy is unsupported!";
}

sub replace {
	croak "replace is unsupported!";
}

sub create_temporary {
	croak "create_temporary is unsupported!";
}

sub delete {
	carp "delete is a no-op in SFTPArchives, please manipulate this repo with install_package, share_package, and remove_package";
	return 1;
}

sub _delete_package($) {
	my $self    = shift;
	my $package = shift;

	if (not defined $package) {
		croak "_delete_package called with undef \$package!";
	}

	# remove $package
	$self->_sftp->remove($package->path) or croak "failed to remove " . $package->path . " from remote repository: " . $self->_sftp->error;
	return 1;
}

sub _add_package($) {
	my $self    = shift;
	my $from    = shift;
	my $to      = shift;

	if (not defined $from) {
		croak "_add_package called with undef \$from!";
	} elsif (not defined $to) {
		croak "_add_package called with undef \$to!";
	}

	# upload $package
	$self->_sftp->mkpath($self->path) or croak "failed to create path " . $self->path . " on the remote repository: " . $self->_sftp->error;
	$self->_sftp->put($from->path, $to->path) or croak "failed to copy " . basename($from->path) . " to " . dirname($to->path) . " on the remote repository: " . $self->_sftp->error;

	return 1;
}

sub delete_package($) {
	my $self    = shift;
	my $package = shift;

	$self->packageset->remove($package);
	if ($self->_in_transaction) {
		$self->_add_transactions->remove($package);
		$self->_del_transactions->add($package);
	} else {
		$self->_delete_package($package);
	}
	return 1;
}

sub copy_package($$) {
	my $self    = shift;
	my $from    = shift;
	my $topath  = shift;

	my $filename = basename($from->path);
	my $finalpath = File::Spec->catfile($self->_get_final_path($topath), $filename);
	my $to = OpenNMS::Release::FilePackage->new($finalpath);

	$self->packageset->add($to);

	if ($self->_in_transaction) {
		$self->_add_transactions->add($to);
		$self->_del_transactions->remove($to);
		$self->_source_packagemap->{$to->path} = $from;
	} else {
		$self->_add_package($from, $to);
	}
	return 1;
}

# no link, just copy
sub link_package($$) {
	shift->copy_package(@_);
}

# no symlink, just copy
sub symlink_package($$) {
	shift->copy_package(@_);
}

sub _add_transactions {
	my $self = shift;
	if (not exists $self->{TRANS_ADD_PACKAGESET}) {
		$self->{TRANS_ADD_PACKAGESET} = OpenNMS::Release::PackageSet->new();
	}
	return $self->{TRANS_ADD_PACKAGESET};
}

sub _del_transactions {
	my $self = shift;
	if (not exists $self->{TRANS_DEL_PACKAGESET}) {
		$self->{TRANS_DEL_PACKAGESET} = OpenNMS::Release::PackageSet->new();
	}
	return $self->{TRANS_DEL_PACKAGESET};
}

sub _original_packageset {
	my $self = shift;
	if (not exists $self->{TRANS_ORIG_PACKAGESET}) {
		$self->{TRANS_ORIG_PACKAGESET} = OpenNMS::Release::PackageSet->new();
	}
	return $self->{TRANS_ORIG_PACKAGESET};
}

sub _source_packagemap {
	my $self = shift;
	if (@_) {
		$self->{TRANS_SOURCE_PACKAGEMAP} = shift;
	}
	if (not exists $self->{TRANS_SOURCE_PACKAGEMAP}) {
		$self->{TRANS_SOURCE_PACKAGEMAP} = {};
	}
	return $self->{TRANS_SOURCE_PACKAGEMAP};
}

sub begin {
	my $self = shift;
	$self->_in_transaction(1);
	$self->_original_packageset->set($self->packageset->find_all);
	$self->_add_transactions->set();
	$self->_del_transactions->set();
	$self->_source_packagemap({});
	return $self;
}

sub abort {
	my $self = shift;
	$self->packageset->set($self->_original_packageset->find_all());
	$self->_add_transactions->set();
	$self->_del_transactions->set();
	$self->_source_packagemap({});
	$self->_in_transaction(0);
	return $self;
}

sub commit {
	my $self = shift;

	for my $package (@{$self->_del_transactions->find_all()}) {
		$self->_delete_package($package);
	}
	for my $package (@{$self->_add_transactions->find_all()}) {
		my $source = $self->_source_packagemap->{$package->path};
		if (not defined $source) {
			croak "unable to determine 'from' file when attempting to upload to " . $package->to_string;
		}
		$self->_add_package($source, $package);
	}
	$self->_add_transactions->set();
	$self->_del_transactions->set();

	$self->_in_transaction(0);
}

sub print_transaction_status {
	my $self = shift;

	if ($self->_in_transaction) {
		print "In transaction: YES\n";
		print "- adds pending:\n";
		for my $package (@{$self->_add_transactions->find_all()}) {
			print "  - ", $package->to_string, "\n";
		}
		print "- deletes pending:\n";
		for my $package (@{$self->_del_transactions->find_all()}) {
			print "  - ", $package->to_string, "\n";
		}
	} else {
		print "In transaction: NO\n";
	}
}

=head2 * index({options})

No-op, remote repositories don't get indexed.

=cut

sub index($) {
	return 1;
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
