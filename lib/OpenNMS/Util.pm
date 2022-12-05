package OpenNMS::Util;

use 5.008008;
use strict;
use warnings;

use Carp;
use File::Spec;
use IO::Handle;

require Exporter;

our @ISA = qw(Exporter);

=head1 NAME

OpenNMS::Util - a collection of utility functions.

=head1 SYNOPSIS

  use OpenNMS::Util;

=cut

our @EXPORT_OK = ( );

our @EXPORT = qw(
	find_executable
	read_properties
	slurp
	spit
	get_gpg_version
	gpg_write_key
	gpg_detach_sign_file
);

our $VERSION = 2.7.0;

=head1 METHODS

=over 4

=item * find_executable($exe)

Locate an executable. It will first look for an all-caps environment variable
pointing to the binary  (RPM = rpm, APT_FTPARCHIVE = apt-ftparchive, etc.), and
check that it is executable, and barring that, look for it in the path.

=cut

sub find_executable {
	my $name = shift;

	my $envname = uc($name);
	$envname =~ s/[^[:alnum:]]+/_/g;

	if (exists $ENV{$envname} and -x $ENV{$envname}) {
		return $ENV{$envname};
	}

	for my $dir (File::Spec->path) {
		my $file = File::Spec->catfile($dir, $name);
		if (-x $file) {
			return $file;
		}
	}
	return;
}

=item * read_properties($file)

Reads a property file and returns a hash of the contents.

=cut

sub read_properties {
	my $file = shift;
	my $return = {};

	my $input = IO::Handle->new();
	open ($input, '<', $file) or die "unable to read from $file: $!";
	while (<$input>) {
		chomp;
		next if (/^\s*$/);
		next if (/^\s*\#/);
		my ($key, $value) = /^\s*([^=]*)\s*=\s*(.*?)\s*$/;
		$return->{$key} = $value;
	}
	close ($input);
	return $return; 
}	       

=item * slurp($file)

Reads the contents of a file and returns it as a string.

=cut

sub slurp {
	my $file = shift;

	my $input = IO::Handle->new();
	open ($input, '<', $file) or die "unable to read from $file: $!";
	local $/ = undef;
	my $ret = <$input>;
	close ($input);
	return $ret;
}

=item * spit($file, $contents)

Writes the contents to the specified file.

=cut

sub spit {
	my $file     = shift;
	my $contents = shift;

	my $output = IO::Handle->new();
	open ($output, '>', $file) or die "unable to write to $file: $!";
	print $output $contents;
	return close($output);
}

=item * get_gpg_version()

Return the GPG major version (1 or 2).

=cut

sub get_gpg_version {
	my $ret = 0;
	my $input = IO::Handle->new();
	open ($input, '-|', 'gpg --version') or die "unable to run gpg --version: $!";
	chomp(my $line = <$input>);
	if ($line =~ /^gpg\s*.*?(\d+)\.[\d\.]+\s*$/) {
		$ret = $1;
	}
	close($input);
	return $ret;
}

=item * gpg_write_key($id, $password, $file)

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

=item * gpg_detach_sign_file($id, $password, $inputfile, [$outputfile])

Given a GPG ID and password, and a file, detach-signs the
specified file and outputs to C<$outputfile>. If no output file
is specified, it creates a file named C<$inputfile.asc>.

=cut

sub gpg_detach_sign_file {
	my $id       = shift;
	my $password = shift;
	my $file     = shift;
	my $output   = shift || $file . '.asc';
	my $sha256   = shift;

	my $command = "gpg --passphrase '$password' --batch --yes -a";
	if ($sha256) {
		$command .= " --digest-algo SHA256";
	}
	$command .= " --default-key '$id' --detach-sign -o '$output' '$file'";

	system($command) == 0 or croak "unable to detach-sign '$file' with GPG id '$id': $!";
	return 1;
}

1;
__END__
=back

=head1 AUTHOR

Benjamin Reed E<lt>ranger@opennms.orgE<gt>
Matt Brozowski E<lt>brozow@opennms.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by The OpenNMS Group, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
