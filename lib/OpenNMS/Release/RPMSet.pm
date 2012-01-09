package OpenNMS::Release::RPMSet;

use 5.008008;
use strict;
use warnings;

use Data::Dumper;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};

	$self->{RPMS} = {};

	bless($self);

	if (@_) {
		$self->add(@_);
	}

	return $self;
}

sub _hash() {
	my $self = shift;
	return $self->{RPMS};
}

sub add(@) {
	my $self = shift;

	my @rpms = ();
	for my $item (@_) {
		if (ref($item) eq "ARRAY") {
			push(@rpms, @{$item});
		} else {
			push(@rpms, $item);
		}
	}

	my %seen = ();
	for my $rpm (@rpms) {
		$self->remove($rpm);
		push(@{$self->_hash->{$rpm->name}->{$rpm->arch}}, $rpm);
		@{$self->_hash->{$rpm->name}->{$rpm->arch}} = sort { $b->compare_to($a) } @{$self->_hash->{$rpm->name}->{$rpm->arch}};
	}
}

sub remove($) {
	my $self = shift;
	my $rpm  = shift;

	my $deleted = 0;
	my $entries = $self->_hash->{$rpm->name}->{$rpm->arch};
	for my $i (0 .. $#{$entries}) {
		if ($entries->[$i]->path eq $rpm->path) {
			$deleted = delete $entries->[$i];
		}
	}
	if (exists $self->_hash->{$rpm->name}->{$rpm->arch} and scalar(@{$self->_hash->{$rpm->name}->{$rpm->arch}}) == 0) {
		delete $self->_hash->{$rpm->name}->{$rpm->arch};
	}
	if (exists $self->_hash->{$rpm->name} and scalar(keys %{$self->_hash->{$rpm->name}}) == 0) {
		delete $self->_hash->{$rpm->name};
	}
	return $deleted;
}

sub set(@) {
	my $self = shift;
	$self->{RPMS} = {};
	$self->add(@_);
}

sub find_all() {
	my $self = shift;
	my @ret = ();
	for my $name (sort keys %{$self->_hash}) {
		for my $arch (sort keys %{$self->_hash->{$name}}) {
			push(@ret, @{$self->_hash->{$name}->{$arch}});
		}
	}
	return \@ret;
}

sub find_newest() {
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

sub find_by_name($) {
	my $self = shift;
	my $name = shift;

	my @ret = ();
	for my $arch (sort keys %{$self->_hash->{$name}}) {
		push(@ret, @{$self->_hash->{$name}->{$arch}});
	}
	return \@ret;
}

sub find_newest_by_name($) {
	my $self = shift;
	my $name = shift;

	my @ret = ();
	for my $arch (sort keys %{$self->_hash->{$name}}) {
		push(@ret, $self->_hash->{$name}->{$arch}->[0]);
	}
	return \@ret;
}

sub find_newest_by_name_and_arch($$) {
	my $self = shift;
	my $name = shift;
	my $arch = shift;

	if (exists $self->_hash->{$name}->{$arch}) {
		return $self->_hash->{$name}->{$arch}->[0];
	}
	return undef;
}

sub find_obsolete() {
	my $self = shift;
	my @ret = grep { $self->is_obsolete($_) } @{$self->find_all()};
	return \@ret;
}

sub is_obsolete($) {
	my $self = shift;
	my $rpm  = shift;

	my $newest = $self->find_newest_by_name_and_arch($rpm->name, $rpm->arch);
	return 0 unless (defined $newest);
	return $newest->is_newer_than($rpm);
}

1;
