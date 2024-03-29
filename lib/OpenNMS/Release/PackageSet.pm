package OpenNMS::Release::PackageSet;

use 5.008008;
use strict;
use warnings;

use Carp;
use Data::Dumper;
use List::Compare;

our $VERSION = 2.9.13;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};

	$self->{PACKAGES} = {};

	bless($self, "OpenNMS::Release::PackageSet");

	if (@_) {
		$self->add(@_);
	}

	return $self;
}

sub _hash {
	my $self = shift;
	return $self->{PACKAGES};
}

sub add {
	my $self = shift;

	my @packages = ();
	for my $item (@_) {
		if (ref($item) eq "ARRAY") {
			push(@packages, @{$item});
		} else {
			push(@packages, $item);
		}
	}

	for my $package (@packages) {
		$self->remove($package);
		push(@{$self->_hash->{$package->name}->{$package->arch}}, $package);
		@{$self->_hash->{$package->name}->{$package->arch}} = sort { $b->compare_to($a) } @{$self->_hash->{$package->name}->{$package->arch}};
	}
}

sub remove {
	my $self    = shift;
	my $package = shift;

	my $deleted = 0;
	my $entries = $self->_hash->{$package->name}->{$package->arch};

	my @keep = grep { $_->path ne $package->path } @{$entries};
	$self->_hash->{$package->name}->{$package->arch} = \@keep;

	if (exists $self->_hash->{$package->name}->{$package->arch} and scalar(@{$self->_hash->{$package->name}->{$package->arch}}) == 0) {
		delete $self->_hash->{$package->name}->{$package->arch};
	}
	if (exists $self->_hash->{$package->name} and scalar(keys %{$self->_hash->{$package->name}}) == 0) {
		delete $self->_hash->{$package->name};
	}
	return $deleted;
}

sub set {
	my $self = shift;
	$self->{PACKAGES} = {};
	$self->add(@_);
}

sub has_newer_than {
	my $self = shift;
	my $other = shift;

	for my $package (@{$self->find_all()}) {
		if ($package->name and $package->arch) {
			my $other_package = $other->find_newest_by_name_and_arch($package->name, $package->arch);
			if (not $other_package) {
				#print STDERR "package " . $package->to_string . " does not exist in the other package set.\n";
				return 1;
			}
			if ($package->is_newer_than($other_package)) {
				#print STDERR "package " . $package->to_string . " is newer than the version in the other package set. (" . $other_package->to_string . ")\n";
				return 1;
			} else {
				#print STDERR "package " . $package->to_string . " is the same or older than the version in the other package set. (" . $other_package->to_string . ")\n";
			}
		}
	}
	return 0;
}

sub find_all {
	my $self = shift;
	my @ret = ();
	for my $name (sort keys %{$self->_hash}) {
		for my $arch (sort keys %{$self->_hash->{$name}}) {
			if (exists $self->_hash->{$name}->{$arch}) {
				push(@ret, @{$self->_hash->{$name}->{$arch}});
			}
		}
	}
	return \@ret;
}

sub find_newest {
	my $self = shift;
	my @ret = ();
	for my $name (sort keys %{$self->_hash}) {
		my $newest = $self->find_newest_by_name($name);
		if (defined $newest) {
			push(@ret, @{$newest});
		}
	}
	return \@ret;
}

sub find_by_name {
	my $self = shift;
	my $name = shift;

	my @ret = ();
	for my $arch (sort keys %{$self->_hash->{$name}}) {
		push(@ret, @{$self->_hash->{$name}->{$arch}});
	}
	return \@ret;
}

sub find_newest_by_name {
	my $self = shift;
	my $name = shift;

	my @ret = ();
	for my $arch (sort keys %{$self->_hash->{$name}}) {
		push(@ret, $self->_hash->{$name}->{$arch}->[0]);
	}
	return \@ret;
}

sub find_newest_by_name_and_arch {
	my $self = shift;
	my $name = shift;
	my $arch = shift;

	if (exists $self->_hash->{$name}->{$arch}) {
		return $self->_hash->{$name}->{$arch}->[0];
	}
	return;
}

sub find_obsolete {
	my $self = shift;
	my @ret = grep { $self->is_obsolete($_) } @{$self->find_all()};
	return \@ret;
}

sub is_obsolete {
	my $self = shift;
	my $package  = shift;

	my $newest = $self->find_newest_by_name_and_arch($package->name, $package->arch);
	return 0 unless (defined $newest);
	return $newest->is_newer_than($package);
}

1;
