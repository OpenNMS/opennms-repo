#!/usr/bin/perl -w

use strict;
use warnings;

$|++;

use Data::Dumper;
use File::Path qw(make_path);
use File::Spec;
use Getopt::Long;
use HTTP::Request;
use JSON::PP qw();
use LWP;
use LWP::Protocol::https;
use URI::Escape;

use vars qw(
  $API_TOKEN
  $INCLUDE_FAILED
  $MATCH
  $PRIME
  $WORKFLOW

  $CIRCLECI_API_ROOT
  $PROJECT_ROOT
);

$INCLUDE_FAILED = 0;
$PRIME = 0;

$CIRCLECI_API_ROOT = 'https://circleci.com/api/v1.1';
$PROJECT_ROOT = $CIRCLECI_API_ROOT . '/project/gh/OpenNMS/opennms';

GetOptions(
  "match=s"        => \$MATCH,
  "prime"          => \$PRIME,
  "token=s"        => \$API_TOKEN,
  "include-failed" => \$INCLUDE_FAILED,
  "workflow=s"     => \$WORKFLOW,
) or die "failed to get options for @ARGV\n";

my $extension   = shift(@ARGV);
my $branch      = shift(@ARGV);
my $download_to = shift(@ARGV) || '.';

if (not defined $branch) {
  print "usage: $0 [--prime] [--include-failed] [--token=circle-api-token] [--workflow=hash] [--match=match] <all|rpm|deb|oci|tgz|tar.gz> <branch> [download-directory]\n\n";
  exit(1);
}

if ($PRIME) {
  $PROJECT_ROOT = $CIRCLECI_API_ROOT . '/project/gh/OpenNMS/opennms-prime';
}

if ($WORKFLOW) {
  $INCLUDE_FAILED = 1;
}

our @EXTENSIONS = ('rpm', 'deb', 'oci', 'tgz', 'tar.gz');
if ($extension ne 'all') {
  @EXTENSIONS = (split(',', $extension));
}

my $agent = LWP::UserAgent->new;
$agent->default_header('Accept', 'application/json');
$agent->ssl_opts(verify_hostname => 0);

if (defined $API_TOKEN) {
  $agent->default_header('Circle-Token', $API_TOKEN);
}

my $url = $PROJECT_ROOT . '/tree/' . uri_escape($branch) . '?limit=100';
my $response = $agent->get($url);
die "Can't get $url: ", $response->status_line, "\n" unless $response->is_success;

my $json = JSON::PP->new->utf8()->relaxed();
my $decoded = $json->decode($response->decoded_content);

my $workflows = [];
my $workflow_mapping = {};

for my $entry (@$decoded) {
  my $build_num = $entry->{'build_num'};
  my $workflow_id = $entry->{'workflows'}->{'workflow_id'};
  my $job_name = $entry->{'workflows'}->{'job_name'};
  my $workflow = {
    id => $workflow_id,
    failed => 0,
    builds => {},
  };

  my $index = $workflow_mapping->{$workflow_id};
  if (defined $index) {
    $workflow = $workflows->[$index];
  } else {
    push(@{$workflows}, $workflow);
    $index = $#$workflows;
    $workflow_mapping->{$workflow_id} = $index;
  }

  if ($entry->{'status'} eq 'failed') {
    $workflow->{'failed'} = 1;
  }

  $workflow->{'builds'}->{$job_name} = $build_num;
}

sub get_artifacts_for_workflow($) {
  my $workflow = shift;
  my $jobs = {};

  for my $job (keys %{$workflow->{'builds'}}) {
    my $build_num = $workflow->{'builds'}->{$job};
    my $artifacts_response = $agent->get($PROJECT_ROOT . '/' . $build_num . '/artifacts');
    die "Can't list artifacts for job $job: ", $artifacts_response->status_line, "\n" unless $artifacts_response->is_success;

    my $artifacts = $json->decode($artifacts_response->decoded_content);
    if (scalar @$artifacts > 0) {
      @$artifacts = map { $_ -> {'url'} } @$artifacts;
      $jobs->{$job} = $artifacts;
    }
  }

  return $jobs;
}

sub download_artifact($$) {
  my ($url, $filename) = @_;

  if (not -d $download_to) {
    make_path($download_to);
  }

  my $output_file = File::Spec->catfile($download_to, $filename);
  my $dl_string = "downloading $filename...";
  print $dl_string;
  open FILEOUT, '>>', $output_file or die "\ncannot open $output_file for writing: $!\n";
  binmode FILEOUT;
  my $amount = 0;
  my $last_time = 0;
  my $request = HTTP::Request->new(GET => $url);
  my $dl_response = $agent->request($request, sub {
    my ($data, $response, $protocol) = @_;
    $amount += length($data);

    my $time = time();
    if ($time != $last_time) {
      $last_time = $time;
      my $mb = scalar($amount / 1024 / 1024);
      printf "\r\%s \%.1fMB", $dl_string, $mb;
    }

    print FILEOUT $data;
  }, 1024 * 64);
  close FILEOUT;
  if (not $dl_response->is_success) {
    unlink($output_file);
    die " failed: ", $dl_response->status_line, "\n";
  }
  print "\r\e[K$dl_string done\n";
}

for my $workflow (@$workflows) {
  if ($WORKFLOW) {
    if ($workflow->{'id'} ne $WORKFLOW) {
      next;
    } else {
      print "Found workflow ${WORKFLOW}.\n";
    }
  }

  my $artifacts = get_artifacts_for_workflow($workflow);

  $workflow->{'artifacts'} = $artifacts;

  if (keys %{$workflow->{'artifacts'}} > 0) {
    if ($INCLUDE_FAILED || not $workflow->{'failed'}) {
      print 'Workflow ', $workflow->{'id'}, ' has ', scalar(keys %{$workflow->{'artifacts'}}), " jobs.\n";
      # print $workflow->{'id'}, ' has artifacts:', Dumper($workflow->{'artifacts'}), "\n";

      for my $job (keys %{$workflow->{'artifacts'}}) {
        for my $artifact (@{$workflow->{'artifacts'}->{$job}}) {
          my ($filename) = $artifact =~ /^.*\/([^\/]+)$/;
          my ($filepart, $ext);
          for my $try (@EXTENSIONS) {
            my $quoted = quotemeta($try);
            if ($filename =~ qr(^(.*)\.${quoted}$)) {
              $filepart = $1;
              $ext = $try;
            # } else {
            #   print "no match: $filename / $quoted\n";
            }
          }
          if (defined $filepart and defined $ext) {
            if (grep { $_ eq $ext } @EXTENSIONS) {
              # print "extension matched: $filepart / $ext\n";
              if (defined $MATCH) {
                my $quoted = quotemeta($MATCH);
                if ($filepart =~ /${quoted}/i) {
                  print "$filepart matches \"$MATCH\". Downloading.\n";
                  download_artifact($artifact, $filename);
                # } else {
                #   print "$filepart does not match $MATCH. Skipping.\n";
                }
              } else {
                download_artifact($artifact, $filename);
              }
            # } else {
            #   print "$filename DOES NOT match: @EXTENSIONS / $filepart / $ext\n";
            }
          }
        }
      }
      last;
    } else {
      print $workflow->{'id'}, " not eligible.\n";
    }
  }
}