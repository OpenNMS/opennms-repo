package OpenNMS::YUM::RPM;

use 5.008008;
use strict;
use warnings;

use Carp;
#use Cwd qw(abs_path);
use Cwd;
use File::Basename;
use File::Copy qw();

=head1 NAME

OpenNMS::YUM::RPM - Perl extension for manipulating RPMs

=head1 SYNOPSIS

  use OpenNMS::YUM::RPM;

  my $rpm = OpenNMS::YUM::RPM->new("path/to/foo.rpm");
  if ($rpm->is_in_repo("path/to")) {
    print "all good!"
  }

=head1 DESCRIPTION

This is just a perl module for manipulating RPMs, including
version comparisons, path comparisons, and other miscellaneous
things.

=cut

our $VERSION = '0.01';

my $CACHE_HITS = 0;
my $CACHE_MISSES = 0;
my $COMPARE_TO_CACHE = {};

=head1 CONSTRUCTOR

=cut

sub stats {
	my $class = shift;
	return {
		cache_hits => $CACHE_HITS,
		cache_misses => $CACHE_MISSES
	};
}

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
		($self->{NAME}, $self->{EPOCH}, $self->{VERSION}, $self->{RELEASE}, $self->{ARCH}) = split(/\|/, $output);
		$self->{EPOCH} = undef if ($self->{EPOCH} eq "(none)");
	} else {
		carp "File was invalid! ($output)";
		return undef;
	}

	bless($self);
	return $self;
}

sub name {
	my $self = shift;
	if (@_) { $self->{NAME} = shift }
	return $self->{NAME};
}

sub epoch {
	my $self = shift;
	if (@_) { $self->{EPOCH} = shift }
	return $self->{EPOCH};
}

sub epoch_int() {
	my $self = shift;
	return 0 unless (defined $self->epoch);
	return $self->epoch;
}

sub version {
	my $self = shift;
	if (@_) { $self->{VERSION} = shift }
	return $self->{VERSION};
}

sub release {
	my $self = shift;
	if (@_) { $self->{RELEASE} = shift }
	return $self->{RELEASE};
}

sub arch {
	my $self = shift;
	if (@_) { $self->{ARCH} = shift }
	return $self->{ARCH};
}

sub path {
	my $self = shift;
	if (@_) { $self->{PATH} = shift }
	return $self->{PATH};
}

sub abs_path() {
	my $self = shift;
	return Cwd::abs_path($self->path);
}

sub relative_path($) {
	my $self = shift;
	my $base = Cwd::abs_path(shift);

	if ($self->abs_path =~ /^${base}\/?(.*)$/) {
		return $1;
	}
	return undef;
}

sub relative_directory($) {
	my $self = shift;
	my $base = shift;
}

sub is_in_repo {
	my $self = shift;
	return defined $self->relative_path(shift);
}

sub full_version {
	my $self = shift;
	return $self->epoch_int . ":" . $self->version . "-" . $self->release;
}

# -1 = self before(compared)
#  0 = equal
#  1 = self after(compared)
sub compare_to {
	my $self       = shift;
	my $compareto  = shift;
	my $use_rpmver = shift || 1;

	my $compareversion = $compareto->full_version;
	my $selfversion    = $self->full_version;

	if (exists $COMPARE_TO_CACHE->{$compareversion}->{$selfversion}) {
		$CACHE_HITS++;
		return $COMPARE_TO_CACHE->{$compareversion}->{$selfversion};
	}

	my $rpmver = `which rpmver 2>/dev/null`;
	chomp($rpmver);
	if ($? == 0 && $use_rpmver) {
		# we have rpmver, defer to it

		if (system("$rpmver '$compareversion' '=' '$selfversion'") == 0) {
			return _cache_comparison($compareversion, $selfversion, 0);
		}
		my $retval = (system("$rpmver '$compareversion' '<' '$selfversion'") >> 8);
		return _cache_comparison($compareversion, $selfversion, 1) if ($retval == 0);
		return _cache_comparison($compareversion, $selfversion, -1);
	}

	# otherwise, attempt to parse ourselves, this will probably
	# not handle all corner cases

	carp "rpmver not found, attempting to parse manually. This is generally a bad idea.";

	return _cache_comparison($compareversion, $selfversion, 1) unless (defined $compareto);

	if ($compareto->epoch_int != $self->epoch_int) {
		# if the compared is lower than the self, return 1 (after)
		return _cache_comparison($compareversion, $selfversion, ($compareto->epoch_int < $self->epoch_int) ? 1 : -1);
	}

	if ($compareto->version eq $self->version) {
		return _cache_comparison($compareversion, $selfversion, _compare_version($compareto->release, $self->release));
	}

	return _cache_comparison($compareversion, $selfversion, _compare_version($compareto->version, $self->version));
}

sub _compare_version {
	my $ver_a = shift;
	my $ver_b = shift;

	my @a = split(!/[[:alnum:]]/, $ver_a);
	my @b = split(!/[[:alnum:]]/, $ver_b);

	my $length_a = length(@a);
	my $length_b = length(@b);

	my $length = ($length_a >= $length_b)? $length_a : $length_b;

	for my $i (0 .. $length) {
		next if ($a[$i] eq $b[$i]);
		return ($a[$i] lt $b[$i]) ? 1 : -1;
	}
}

sub _cache_comparison {
	my $compareversion = shift;
	my $selfversion    = shift;
	my $result         = shift;

	$CACHE_MISSES++;
	$COMPARE_TO_CACHE->{$compareversion}->{$selfversion} = $result;
	return $result;
}

sub equals($) {
	my $self      = shift;
	my $compareto = shift;

	return $self->compare_to($compareto) == 0;
}

sub is_newer_than($) {
	my $self      = shift;
	my $compareto = shift;

	return $self->compare_to($compareto) == 1;
}

sub is_older_than($) {
	my $self     = shift;
	my $compareto = shift;

	return $self->compare_to($compareto) == -1;
}

sub delete() {
	my $self = shift;
	return unlink($self->abs_path);
}

sub copy($) {
	my $self = shift;
	my $to   = shift;

	my $filename = $self->_get_filename_for_target($to);

	unlink $filename if (-e $filename);
	my $ret = File::Copy::copy($self->abs_path, $filename);
	return $ret? OpenNMS::YUM::RPM->new($filename) : undef;
}

sub link($) {
	my $self = shift;
	my $to   = shift;

	my $filename = $self->_get_filename_for_target($to);

	unlink $filename if (-e $filename);
	my $ret = link($self->abs_path, $filename);
	return $ret? OpenNMS::YUM::RPM->new($filename) : undef;
}

sub symlink($) {
	my $self = shift;
	my $to   = shift;

	my $filename = $self->_get_filename_for_target($to);
	my $from = File::Spec->abs2rel($self->abs_path, dirname($filename));

	unlink $filename if (-e $filename);
	my $ret = symlink($from, $filename);
	return $ret? OpenNMS::YUM::RPM->new($filename) : undef;
}

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
# Below is stub documentation for your module. You'd better edit it!


=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

A. U. Thor, E<lt>ranger@localdomainE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by A. U. Thor

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
