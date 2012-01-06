package OpenNMS::Util;

use 5.008008;
use strict;
use warnings;

use Carp;
require Exporter;

our @ISA = qw(Exporter);

=head1 NAME

OpenNMS::Util - a collection of utility functions.

=head1 SYNOPSIS

  use OpenNMS::Util;

=cut

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use OpenNMS::YUM ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	read_properties
	slurp
	gpg_write_key
	gpg_detach_sign_file
);

our $VERSION = '0.7';

=head1 METHODS

=head2 * read_properties($file)

Reads a property file and returns a hash of the contents.

=cut

sub read_properties {
	my $file = shift;
	my $return = {};

	open (FILEIN, $file) or die "unable to read from $file: $!";
	while (<FILEIN>) {
		chomp;
		next if (/^\s*$/);
		next if (/^\s*\#/);
		my ($key, $value) = /^\s*([^=]*)\s*=\s*(.*?)\s*$/;
		$return->{$key} = $value;
	}
	close (FILEIN);
	return $return; 
}	       

=head2 * slurp($file)

Reads the contents of a file and returns it as a string.

=cut

sub slurp {
	my $file = shift;
	open (FILEIN, $file) or die "unable to read from $file: $!";
	local $/ = undef;
	my $ret = <FILEIN>;
	close (FILEIN);
	return $ret;
}

=head2 * gpg_write_key($id, $password, $file)

Given a GPG ID and password, and an output file, writes
the ASCII-armored version of the GPG key to the given file.

=cut

sub gpg_write_key {
	my $id       = shift;
	my $password = shift;
	my $output   = shift;

	system("gpg --passphrase '$password' --batch --yes -a --export '$id' > $output") == 0 or croak "unable to write public key for '$id' to '$output': $!";
	return 1;
}

=head2 * gpg_detach_sign_file($id, $password, $file)

Given a GPG ID and password, and a file, detach-signs the
specified file. This creates a file named C<$file.asc>.

=cut

sub gpg_detach_sign_file {
	my $id       = shift;
	my $password = shift;
	my $file     = shift;

	system("gpg --passphrase '$password' --batch --yes -a --default-key '$id' --detach-sign $file") == 0 or croak "unable to detach-sign '$file' with GPG id '$id': $!";
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
