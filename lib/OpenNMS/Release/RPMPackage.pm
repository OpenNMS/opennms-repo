package OpenNMS::Release::RPMPackage;

use 5.008008;
use strict;
use warnings;

use Carp;
use Cwd;
use Expect;
use File::Basename;
use File::Copy qw();
use IO::Handle;
use IPC::Open2;

use base qw(OpenNMS::Release::LocalPackage);

use OpenNMS::Util 2.5.0;
use OpenNMS::Release::RPMVersion;

=head1 NAME

OpenNMS::Release::RPMPackage - Perl extension for manipulating RPMs

=head1 SYNOPSIS

  use OpenNMS::Release::RPMPackage;

  my $rpm = OpenNMS::Release::RPMPackage->new("path/to/foo.rpm");

=head1 DESCRIPTION

This is just a perl module for manipulating RPMs, including
version comparisons, path comparisons, and other miscellaneous
things.

=cut

our $VERSION = 2.6.7;

our $RPM     = undef;
our $RPMSIGN = undef;

=head1 CONSTRUCTOR

OpenNMS::Release::RPMPackage->new($path)

Given a path to an RPM file, create a new OpenNMS::Release::RPMPackage object.
The RPM file must exist.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $path  = shift;

	if (not defined $path) {
		carp "You did not provide a path!";
		return undef;
	}

	if (not defined $RPMSIGN) {
		$RPMSIGN = find_executable('rpmsign');
		if (not defined $RPMSIGN) {
			croak "Unable to locate \`rpmsign\`: $!";
		}
	}

	my $escaped_path = $path;
	$escaped_path =~ s/\'/\\\'/g;

	if (not defined $RPM) {
		$RPM = find_executable('rpm');
		if (not defined $RPM) {
			croak "Unable to locate \`rpm\`: $!";
		}
	}

	my $output = `$RPM -q --queryformat='\%{name}|\%{epoch}|\%{version}|\%{release}|\%{arch}' -p '$escaped_path'`;
	chomp($output);
	if ($? == 0) {
		my ($name, $epoch, $version, $release, $arch) = split(/\|/, $output);
		$epoch = undef if ($epoch eq "(none)");
		$version = OpenNMS::Release::RPMVersion->new($version, $release, $epoch);
		return bless($class->SUPER::new($path, $name, $version, $arch), $class);
	} else {
		carp "File was invalid! ($output)";
		return undef;
	}
}

=head1 METHODS

=head2 * sign($id, $password)

Given a GPG id and password, sign (or resign) the RPM.

=cut

sub sign ($$) {
	my $self	 = shift;
	my $gpg_id       = shift;
	my $gpg_password = shift;

	system($RPMSIGN, '--delsign', $self->path) == 0 or die "Can't run $RPMSIGN --delsign on " . $self->to_string;

	my $expect = Expect->new();
	$expect->raw_pty(1);
	$expect->spawn($RPMSIGN, '--quiet', "--define=_gpg_name $gpg_id", '--resign', $self->path) or die "Can't spawn $RPMSIGN: $!";

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

=head1 * description()

Get the description of the RPM.

=cut

sub description() {
	my $self = shift;

	my $output = IO::Handle->new();
	my $input  = IO::Handle->new();
	my $pid = open2($output, $input, $RPM, '-q', '-i', '-p', $self->path) or die "Can't spawn $RPM -qip " . $self->path . ": " . $!;
	close($input);
	my $return = do { local $/; <$output> };
	close($output);
	waitpid($pid, 0);

	return $return; 
}

1;
__END__
=head1 AUTHOR

Benjamin Reed, E<lt>ranger@opennms.orgE<gt>
Matt Brozowski, E<lt>brozow@opennms.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by The OpenNMS Group, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
