package OpenNMS::Release::RPM;

use 5.008008;
use strict;
use warnings;

use Carp;
#use Cwd qw(abs_path);
use Cwd;
use File::Basename;
use File::Copy qw();
use Expect;

use OpenNMS::Release::RPM::Version;

=head1 NAME

OpenNMS::Release::RPM - Perl extension for manipulating RPMs

=head1 SYNOPSIS

  use OpenNMS::Release::RPM;

  my $rpm = OpenNMS::Release::RPM->new("path/to/foo.rpm");
  if ($rpm->is_in_repo("path/to")) {
    print "all good!"
  }

=head1 DESCRIPTION

This is just a perl module for manipulating RPMs, including
version comparisons, path comparisons, and other miscellaneous
things.

=cut

our $VERSION = '1.1';

=head1 CONSTRUCTOR

OpenNMS::Release::RPM->new($path)

Given a path to an RPM file, create a new OpenNMS::Release::RPM object.
The RPM file must exist.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};

	my $path = shift;

	if (not defined $path) {
		carp "You did not provide a path!";
		return undef;
	}

	$path = Cwd::abs_path($path);
	$self->{PATH} = $path;
	$path =~ s/\'/\\\'/g;
	my $output = `rpm -q --queryformat='\%{name}|\%{epoch}|\%{version}|\%{release}|\%{arch}' -p '$path'`;
	chomp($output);
	if ($? == 0) {
		my ($name, $epoch, $version, $release, $arch) = split(/\|/, $output);
		$epoch = undef if ($epoch eq "(none)");
		$self->{NAME} = $name;
		$self->{ARCH} = $arch;
		$self->{VERSION} = OpenNMS::Release::RPM::Version->new($version, $release, $epoch);
	} else {
		carp "File was invalid! ($output)";
		return undef;
	}

	bless($self);
	return $self;
}

=head1 METHODS

=head2 * name

The name of the RPM, i.e., "opennms".

=cut

sub name {
	my $self = shift;
	return $self->{NAME};
}

=head2 * rpm_version

The RPM version, in an OpenNMS::Release::RPM::Version object.

=cut

sub rpm_version {
	my $self = shift;
	return $self->{VERSION};
}

=head2 * epoch

The epoch of the RPM.  If no epoch is set, returns undef.

=cut

sub epoch {
	my $self = shift;
	return $self->rpm_version->epoch;
}

=head2 * epoch_int

The epoch of the RPM.  If no epoch is set, returns the default epoch, 0.

=cut

sub epoch_int() {
	my $self = shift;
	return $self->rpm_version->epoch_int;
}

=head2 * version

The version of the RPM. This is generally the same as the version of the
upstream software that was packaged.

=cut

sub version {
	my $self = shift;
	return $self->rpm_version->version;
}

=head2 * release

The release of the RPM. This is generally a number determined by the packager
to track changes to the RPM, independent of version changes in the software
that is packaged.

=cut

sub release {
	my $self = shift;
	return $self->rpm_version->release;
}

=head2 * arch

The architecture of the RPM. (e.g., "noarch", "i386", etc.)

=cut

sub arch {
	my $self = shift;
	return $self->{ARCH};
}

=head2 * path

The path to the RPM. This will always be initialized as the absolute path
to the RPM file.

=cut

sub path {
	my $self = shift;
	return $self->{PATH};
}

=head2 * abs_path

The absolute path to the RPM. (Deprecated)

=cut

sub abs_path() {
	my $self = shift;
	return Cwd::abs_path($self->path);
}

=head2 * relative_path($base)

Given a base directory, returns the path of this RPM, relative to that base path.

=cut

sub relative_path($) {
	my $self = shift;
	my $base = Cwd::abs_path(shift);

	if ($self->abs_path =~ /^${base}\/?(.*)$/) {
		return $1;
	}
	return undef;
}

=head2 * is_in_repo($path)

Given a repository path, returns true if the RPM is contained in the given
repository path.

=cut

sub is_in_repo {
	my $self = shift;
	return defined $self->relative_path(shift);
}

=head2 * full_version

Returns the complete version string of the RPM, in the form: C<epoch:version-release>

=cut

sub full_version {
	my $self = shift;
	return $self->rpm_version->full_version;
}

=head2 * display_version

Returns the complete version string, just like full_version, expect it excludes
the epoch if there is no epoch in the RPM.

=cut

sub display_version {
	my $self = shift;
	return $self->rpm_version->display_version;
}

=head2 * compare_to($rpm)

Given an RPM, performs a cmp-style comparison on the RPMs' name and version, for
use in sorting.

=cut

# -1 = self before(compared)
#  0 = equal
#  1 = self after(compared)
sub compare_to {
	my $self       = shift;
	my $compareto  = shift;
	my $use_rpmver = shift || 1;

	if ($compareto->name ne $self->name) {
		return $compareto->name cmp $self->name;
	}

	my $compareversion = $compareto->rpm_version;
	my $selfversion    = $self->rpm_version;

	return $selfversion->compare_to($compareversion);
}

=head2 * equals($rpm)

Given an RPM, returns true if both RPMs have the same name and version.

=cut

sub equals($) {
	my $self      = shift;
	my $compareto = shift;

	return $self->compare_to($compareto) == 0;
}

=head2 * is_newer_than($rpm)

Given an RPM, returns true if the current RPM is newer than the
given RPM, and they have the same name.

=cut

sub is_newer_than($) {
	my $self      = shift;
	my $compareto = shift;

	return 0 if ($self->name ne $compareto->name);
	return $self->compare_to($compareto) == 1;
}

=head2 * is_older_than($rpm)

Given an RPM, returns true if the current RPM is older than the
given RPM, and they have the same name.

=cut

sub is_older_than($) {
	my $self     = shift;
	my $compareto = shift;

	return 0 if ($self->name ne $compareto->name);
	return $self->compare_to($compareto) == -1;
}

=head2 * delete

Delete the RPM from the filesystem.

=cut

sub delete() {
	my $self = shift;
	return unlink($self->abs_path);
}

=head2 * copy($target_path)

Given a target path, copy the current RPM to that path.

=cut

sub copy($) {
	my $self = shift;
	my $to   = shift;

	my $filename = $self->_get_filename_for_target($to);

	unlink $filename if (-e $filename);
	my $ret = File::Copy::copy($self->abs_path, $filename);
	return $ret? OpenNMS::Release::RPM->new($filename) : undef;
}

=head2 * link($target_path)

Given a target path, hard link the current RPM to that path.

=cut

sub link($) {
	my $self = shift;
	my $to   = shift;

	my $filename = $self->_get_filename_for_target($to);

	unlink $filename if (-e $filename);
	my $ret = link($self->abs_path, $filename);
	return $ret? OpenNMS::Release::RPM->new($filename) : undef;
}

=head2 * symlink($target_path)

Given a target path, symlink the current RPM to that path, relative to
the source RPM's location.

=cut

sub symlink($) {
	my $self = shift;
	my $to   = shift;

	my $filename = $self->_get_filename_for_target($to);
	my $from = File::Spec->abs2rel($self->abs_path, dirname($filename));

	unlink $filename if (-e $filename);
	my $ret = symlink($from, $filename);
	return $ret? OpenNMS::Release::RPM->new($filename) : undef;
}

=head2 * sign($id, $password)

Given a GPG id and password, sign (or resign) the RPM.

=cut

sub sign ($$) {
	my $self         = shift;
	my $gpg_id       = shift;
	my $gpg_password = shift;

	my $rpmsign = `which rpmsign 2>/dev/null`;
	if ($? != 0) {
		carp "Unable to locate \`rpmsign\`!";
		return 0;
	}
	chomp($rpmsign);

	my $expect = Expect->new();
	$expect->raw_pty(1);
	$expect->spawn($rpmsign, '--quiet', "--define=_gpg_name $gpg_id", '--resign', $self->abs_path) or die "Can't spawn $rpmsign: $!";

	$expect->expect(60, [
		qr/Enter pass phrase:\s*/ => sub {
			my $exp = shift;
			$exp->send($gpg_password . "\n");
			exp_continue;
		}
	]);
	$expect->soft_close();
	return $expect->exitstatus() == 0;
}

=head2 * to_string

Returns a string representation of the RPM, suitable for printing.

=cut

sub to_string() {
	my $self = shift;
	return $self->name . '-' . $self->full_version . ' (' . $self->abs_path . ')';
}

sub _get_filename_for_target($) {
	my $self = shift;
	my $to   = shift;

	if (-d $to) {
		if ($to !~ /\/$/) {
			$to .= "/";
		}
		$to = $to . basename($self->path);
	}
	return $to;
}

1;
__END__
=head1 AUTHOR

Benjamin Reed, E<lt>ranger@opennms.orgE<gt>
Matt Brozowski, E<lt>brozow@opennms.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by The OpenNMS Group, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
