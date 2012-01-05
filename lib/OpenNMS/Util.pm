package OpenNMS::Util;

use 5.008008;
use strict;
use warnings;

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
);

our $VERSION = '0.5';

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

sub slurp {
	my $file = shift;
	open (FILEIN, $file) or die "unable to read from $file: $!";
	local $/ = undef;
	my $ret = <FILEIN>;
	close (FILEIN);
	return $ret;
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
