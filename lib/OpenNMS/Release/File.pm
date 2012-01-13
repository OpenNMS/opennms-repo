package OpenNMS::Release::File;

use 5.008008;
use strict;
use warnings;

use Carp;
use Cwd;
use File::Basename;
use File::Copy qw();
use File::Spec;

use OpenNMS::Release::Version;

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
	my $self  = {};
	my $path  = shift;

	if (not File::Spec->file_name_is_absolute($path)) {
		croak "path $path is not absolute!";
	}

	$self->{PATH} = $path;

	bless($self);
	return $self;
}

=head1 METHODS

=head2 * path

The path to the file.

=cut

sub path {
	my $self = shift;
	return $self->{PATH};
}

=head2 * relative_path($base)

Given a base directory, returns the path of this file, relative to that base path.

=cut

sub relative_path($) {
	my $self = shift;
	my $base = Cwd::abs_path(shift);

	if ($self->path =~ /^${base}\/?(.*)$/) {
		return $1;
	}
	return undef;
}

=head2 * is_in_path($path)

Given a repository path, returns true if the file is contained in the given path.

=cut

sub is_in_path {
	my $self = shift;
	return defined $self->relative_path(shift);
}

=head2 * equals($file)

Given a file, returns true if both files have the same name and version.

=cut

sub equals($) {
	my $this = shift;
	my $that = shift;

	return $this->path eq $that->path;
}

=head2 * delete

Delete the file from the filesystem.

=cut

sub delete() {
	my $self = shift;
	return unlink($self->path);
}

=head2 * copy($target_path)

Given a target path, copy the current file to that path.

=cut

sub copy($) {
	my $self = shift;
	my $to   = shift;

	my $filename = $self->_get_filename_for_target($to);

	unlink $filename if (-e $filename);
	my $ret = File::Copy::copy($self->path, $filename);

	return $ret? $self->new($filename) : undef;
}

=head2 * link($target_path)

Given a target path, hard link the current file to that path.

=cut

sub link($) {
	my $self = shift;
	my $to   = shift;

	my $filename = $self->_get_filename_for_target($to);

	unlink $filename if (-e $filename);
	my $ret = link($self->path, $filename);
	return $ret? $self->new($filename) : undef;
}

=head2 * symlink($target_path)

Given a target path, symlink the current file to that path, relative to
the source file's location.

=cut

sub symlink($) {
	my $self = shift;
	my $to   = shift;

	my $filename = $self->_get_filename_for_target($to);
	my $from = File::Spec->abs2rel($self->path, dirname($filename));

	unlink $filename if (-e $filename);
	my $ret = symlink($from, $filename);
	return $ret? $self->new($filename) : undef;
}

=head2 * to_string

Returns a string representation of the file, suitable for printing.

=cut

sub to_string() {
	my $self = shift;
	return $self->path;
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
