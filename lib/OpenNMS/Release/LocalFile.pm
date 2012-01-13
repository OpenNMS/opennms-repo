package OpenNMS::Release::LocalFile;

use 5.008008;
use strict;
use warnings;

use Carp;

use base qw(OpenNMS::Release::File);

=head1 NAME

OpenNMS::Release::File - Perl extension for manipulating files

=head1 SYNOPSIS

  use OpenNMS::Release::File;

  my $file = OpenNMS::Release::File->new("path/to/foo");
  if ($file->is_in_path("path/to")) {
    print "all good!"
  }

=head1 DESCRIPTION

This is a perl module for manipulating files.

=cut

our $VERSION = '2.1';

=head1 CONSTRUCTOR

OpenNMS::Release::File->new($path);

Given a path to a file, create a new OpenNMS::Release::File object.
The path must be absolute, but does not have to exist.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $path  = shift;

	if (not -e $path) {
		croak "path $path does not exist!";
	}

	return bless($class->SUPER::new($path), $class);
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
