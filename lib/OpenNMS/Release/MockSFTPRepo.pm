package OpenNMS::Release::MockSFTPRepo;

use 5.008008;
use strict;
use warnings;

use Carp;
use File::Basename;

use base qw(OpenNMS::Release::SFTPRepo);

our $VERSION = 2.9.10;

sub _init {
	return 1;
}

sub _packageset {
	my $self = shift;

	my @packages = ();

	for my $file (qw(
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.16-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.15-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.0-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.0-2.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.1-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.10-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.10-2.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.11-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.2-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.3-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.4-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.5-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.7-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.8-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.9-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.9-2.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.0-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.1-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.2-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.3-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.3-2.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.4-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.5-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.6-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.7-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.12-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.8-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.13-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.90-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.8.14-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.91-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.92-1.tar.gz
		/home/frs/project/o/op/opennms/OpenNMS-Source/opennms-source-1.9.93-1.tar.gz
	)) {
		push(@packages, OpenNMS::Release::FilePackage->new($file));
	}
	return OpenNMS::Release::PackageSet->new(\@packages);
	
}

sub _delete_package($) {
	my $self    = shift;
	my $package = shift;

	#carp "(mock)_delete_package(" . $package->to_string . ")";
}

sub _add_package($$) {
	my $self    = shift;
	my $from    = shift;
	my $to      = shift;

	#carp "(mock)_add_package(" . $package->to_string . ")";
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
