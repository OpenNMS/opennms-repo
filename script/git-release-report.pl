#!/usr/bin/env perl

$|++;

use Data::Dumper;
use Git;
use JIRA::REST;
use Try::Tiny;

my $from = shift @ARGV;
my $to   = shift @ARGV;
my $dir  = shift @ARGV || '.';

if (not defined $to) {
  print <<END;
usage: $0 <from-ref> <to-ref> [working directory]

example: $0 opennms-26.2.1-1 develop ~/git/opennms

You will need to create a ~/.netrc file (mode 600) first:

machine issues.opennms.org
login <your-username>
password <your-password>

END
  exit(0);
}

my $matches = {};

my $repo = Git->repository(Directory => $dir);
my $last_commit;

# '--no-merges', 
for my $line ($repo->command('log', $from . '..' . $to)) {
  if ($line =~ /^commit (.+)$/) {
    $last_commit = $1;
  } elsif ($line =~ /^[A-Z][[:alnum:]]+\: /) {
    # header of some kind
    next;
  } else {
    while ($line =~ /\b([A-Z]{2,}-[0-9]+)\b/gsi) {
      my $match = uc($1);
      if (not defined $matches->{$match}) {
        $matches->{$match} = [];
      }
      push(@{$matches->{$match}}, $last_commit);
    }
  }
}

my $jira = JIRA::REST->new({
  url => 'https://issues.opennms.org/'
});

for my $key (sort keys %$matches) {
  try {
    my $issue = $jira->GET("/issue/$key");
    print "* [$key](https://issues.opennms.org/browse/$key)", ': ', $issue->{'fields'}->{'summary'}, "\n";
#  } catch {
#    print "error ($key): $err\n";
  }
}
