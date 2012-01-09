package OpenNMS::Release::RPMPackage;

use 5.008008;
use strict;
use warnings;

use Carp;
use Cwd;
use File::Basename;
use File::Copy qw();
use Expect;

use base qw(OpenNMS::Release::Package);

use OpenNMS::Release::RPMVersion;

=head1 NAME

OpenNMS::Release::RPMPackage - Perl extension for manipulating RPMs

=head1 SYNOPSIS

  use OpenNMS::Release::RPMPackage;

  my $rpm = OpenNMS::Release::RPMPackage->new("path/to/foo.rpm");
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

OpenNMS::Release::RPMPackage->new($path)

Given a path to an RPM file, create a new OpenNMS::Release::RPMPackage object.
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

	my $escaped_path = $path;
	$escaped_path =~ s/\'/\\\'/g;
	my $output = `rpm -q --queryformat='\%{name}|\%{epoch}|\%{version}|\%{release}|\%{arch}' -p '$escaped_path'`;
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
	$expect->spawn($rpmsign, '--quiet', "--define=_gpg_name $gpg_id", '--resign', $self->path) or die "Can't spawn $rpmsign: $!";

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
