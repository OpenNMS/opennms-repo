#!/usr/bin/perl -w

$|++;

use strict;
use warnings;

use File::Slurp;

use OpenNMS::Release;
use OpenNMS::Release::DebPackage;
use OpenNMS::Release::RPMPackage;

use vars qw(
  $PASSWORD
);

if (@ARGV == 0) {
	print "usage: $0 <file> [...files]\n\n";
	exit(1);
}


my $passfile = File::Spec->catfile($ENV{'HOME'}, '.signingpass');
if (-e $passfile) {
  chomp($PASSWORD = read_file($passfile));
} else {
  print STDERR "ERROR: $passfile does not exist!  New RPMs will not be signed!";
  exit(1);
}

for my $file (@ARGV) {
  my $package;
  if ($file =~ /\.deb$/) {
    $package = OpenNMS::Release::DebPackage->new($file);
  } elsif ($file =~ /\.rpm$/) {
    $package = OpenNMS::Release::RPMPackage->new($file);
  } else {
    print "WARNING: unknown file type, ignoring: $file\n";
  }
  if ($package) {
    print "signing " . $package->name() . "\n";
    $package->sign('opennms@opennms.org', $PASSWORD);
  }
}
