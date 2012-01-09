package OpenNMS::Release::RPMSet;

use 5.008008;
use strict;
use warnings;

use Data::Dumper;
use OpenNMS::Release::RPM;

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
		push(@{$self->_hash->{$rpm->name}}, $rpm);
		@{$self->_hash->{$rpm->name}} = sort { $b->compare_to($a) } @{$self->_hash->{$rpm->name}};
	}
}

sub remove($) {
	my $self = shift;
	my $rpm  = shift;

	my $entries = $self->_hash->{$rpm->name};
	for my $i (0 .. $#{$entries}) {
		if ($entries->[$i]->abs_path eq $rpm->abs_path) {
			return delete $entries->[$i];
		}
	}
}

sub set(@) {
	my $self = shift;
	$self->{RPMS} = {};
	$self->add(@_);
}

sub find_all() {
	my $self = shift;
	my @ret = ();
	for my $key (sort keys %{$self->_hash}) {
		push(@ret, @{$self->_hash->{$key}});
	}
	return \@ret;
}

sub find_newest() {
	my $self = shift;
	my @ret = ();
	for my $key (sort keys %{$self->_hash}) {
		my $newest = $self->find_newest_by_name($key);
		if (defined $newest) {
			push(@ret, @{$newest});
		}
	}
	return \@ret;
}

sub find_by_name($) {
	my $self = shift;
	my $name = shift;
	return $self->_hash->{$name};
}

sub find_newest_by_name($) {
	my $self = shift;
	my $name = shift;
	my $found = $self->find_by_name($name);
	if (defined $found) {
		my $arches = {};
		my @newest = ();
		for my $rpm (@$found) {
			if (not exists $arches->{$rpm->arch}) {
				push(@newest, $rpm);
				$arches->{$rpm->arch}++;
			}
		}
		return \@newest;
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

	my $newest = $self->find_newest_by_name($rpm->name);
	return 0 unless (defined $newest);
	for my $newest_rpm (@$newest) {
		if ($newest_rpm->is_newer_than($rpm) and $newest_rpm->arch eq $rpm->arch) {
			return 1;
		}
	}
	return 0;
}

1;
