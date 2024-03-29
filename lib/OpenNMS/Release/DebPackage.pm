package OpenNMS::Release::DebPackage;

use 5.008008;
use strict;
use warnings;

use Carp;
use Cwd;
use File::Basename;
use File::Copy qw();
use IO::Handle;
use Expect;

use base qw(OpenNMS::Release::LocalPackage);

use OpenNMS::Util 2.5.0;
use OpenNMS::Release::DebVersion;

=head1 NAME

OpenNMS::Release::DebPackage - Perl extension for manipulating Debian packages

=head1 SYNOPSIS

  use OpenNMS::Release::DebPackage;

  my $deb = OpenNMS::Release::DebPackage->new("path/to/foo.deb");

=head1 DESCRIPTION

This is just a perl module for manipulating Debian packages, including
version comparisons, path comparisons, and other miscellaneous
things.

=cut

our $DPKG_SIG = undef;
our $DEBSIGS  = undef;
our $VERSION = '2.9.14';

=head1 CONSTRUCTOR

OpenNMS::Release::DebPackage->new($path)

Given a path to a .deb file, create a new OpenNMS::Release::DebPackage object.
The file must exist.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $path = shift;

	if (not defined $path) {
		carp "You did not provide a path!";
		return;
	}

	if (not defined $DEBSIGS) {
		$DEBSIGS = find_executable('debsigs');
		if (not defined $DEBSIGS) {
			croak "Unable to locate debsigs!  Try \`apt-get install debsigs\`.";
		}
	}

	if (not defined $DPKG_SIG) {
		$DPKG_SIG = find_executable('dpkg-sig');
		if (not defined $DPKG_SIG) {
			croak "Unable to locate dpkg-sig! Try \`apt-get install dpkg-sig`.";
		}
	}

	my $escaped_path = $path;
	$escaped_path =~ s/\'/\\\'/g;

	my $handle = IO::Handle->new();
	open($handle, "-|", "dpkg-deb -f '$escaped_path' package version architecture") or croak "Unable to run dpkg-deb -f '$escaped_path': $!";
	my $d_package = <$handle>;
	my $d_version = <$handle>;
	my $d_architecture = <$handle>;
	close($handle);

	if (not $d_package =~ s/^Package:\s*(.*?)\s*\r?\n?$/$1/) {
		carp "Unable to determine package name from output: $d_package";
		return;
	}
	if (not $d_version =~ s/^Version:\s*(.*?)\s*\r?\n?$/$1/) {
		carp "Unable to determine package version from output: $d_version";
		return;
	}
	if (not $d_architecture =~ s/^Architecture:\s*(.*?)\s*\r?\n?$/$1/) {
		carp "Unable to determine package arch from output: $d_architecture";
		return;
	}

	my $name = $d_package;
	my ($epoch, $version, $release, $arch);
	if ($d_version =~ /^[\d\.\+]+\:/) {
		($epoch, $version, $release) = $d_version =~ /^([\d\.\+]+):([^\-]+)-(.*?)$/;
	} elsif ($d_version =~ /-/) {
		($version, $release) = $d_version =~ /^([^\-]+)-(.*?)$/;
	} else {
		($version) = $d_version =~ /^([\d\.\+]+)$/;
		$release = 0;
	}
	$version = OpenNMS::Release::DebVersion->new($version, $release, $epoch);
	$arch = $d_architecture;

	return bless($class->SUPER::new($path, $name, $version, $arch), $class);
}

=head1 METHODS

=head2 * sign($id, $password)

Given a GPG id and password, sign (or resign) the Debian package.

=cut

sub sign {
	my $self         = shift;
	my $gpg_id       = shift;
	my $gpg_password = shift;

	my $expect = Expect->new();
	$expect->raw_pty(1);
	#$expect->spawn($DPKG_SIG, '--sign', 'builder', '-k', $gpg_id, $self->path) or die "Can't spawn $DPKG_SIG: $!";
	$expect->spawn($DEBSIGS, '--sign', 'archive', '--verify', '-k', $gpg_id, $self->path) or die "Can't spawn $DEBSIGS: $!";

	$expect->expect(60, [
		qr/Enter passphrase:\s*/ => sub {
			my $exp = shift;
			$exp->send($gpg_password . "\n");
			exp_continue;
		}
	]);
	$expect->soft_close();
	return $expect->exitstatus() == 0;
}

1;
__END__
=head1 AUTHOR

Benjamin Reed, E<lt>ranger@opennms.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by The OpenNMS Group, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
