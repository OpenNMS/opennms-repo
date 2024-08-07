#!/usr/bin/env perl

use strict;
use warnings;

$|++;

use Data::Dumper;
use DateTime::Format::ISO8601;
use File::Path qw(make_path);
use File::Spec;
use Getopt::Long;
use HTTP::Request;
use JSON::PP qw();
use LWP;
use LWP::Protocol::https;
use LWP::UserAgent::Determined;
use URI::Escape;

use vars qw(
  $API_TOKEN
  $CI
  $HELP
  $INCLUDE_FAILED
  $MATCH
  $PRIME
  $REPO
  $VAULT
  $WAIT_TIME
  $WORKFLOW

  $CIRCLECI_API_ROOT
  $PROJECT_ROOT
);

$CI = 0;
$HELP = 0;
$INCLUDE_FAILED = 0;
$PRIME = 0;
$REPO = "opennms";
$VAULT = 0;
$WAIT_TIME = 2; # seconds

if ($ENV{'CIRCLE_TOKEN'}) {
  $API_TOKEN = $ENV{'CIRCLE_TOKEN'};
}

if ($ENV{'CIRCLE_WORKFLOW_ID'}) {
  $WORKFLOW = $ENV{'CIRCLE_WORKFLOW_ID'};
}

our $VAULT_MAPPING = [
  [ qr/\.ya?ml$/                                                  => 'yml'        ],
  [ qr/\.xml$/                                                    => 'xml'        ],
  [ qr/\.oci$/                                                    => 'oci'        ],
  [ qr/\.rpm$/                                                    => 'rpm'        ],
  [ qr/\.(changes|deb)$/                                          => 'deb'        ],
  [ qr/-(docs|javadoc|xsds)\.tar\.gz$/                            => 'docs'       ],
  [ qr/(horizon|meridian|opennms)-[\d\.]+(-SNAPSHOT)?\.tar\.gz$/  => 'standalone' ],
  [ qr/(minion|sentinel)-[\d\.]+(-SNAPSHOT)?\.tar\.gz$/           => 'standalone' ],
  [ qr/remote-poller-client-[\d\.]+(-SNAPSHOT)?\.tar\.gz$/        => 'standalone' ],
];

$CIRCLECI_API_ROOT = 'https://circleci.com/api/v1.1';
$PROJECT_ROOT = $CIRCLECI_API_ROOT . '/project/gh/OpenNMS/opennms-omega';

sub usage {
  print "usage: $0 [--ci] [--vault-layout] [--repo=repo] [--include-failed] [--token=circle-api-token] [--workflow=hash] [--match=match] <all|deb|rpm|oci|json|tgz|tar.gz|xml|yml> <branch> [download-directory]\n\n";
  exit(1);
}

GetOptions(
  "help"           => \$HELP,
  "match=s"        => \$MATCH,
  "prime"          => \$PRIME,
  "repo=s"         => \$REPO,
  "token=s"        => \$API_TOKEN,
  "include-failed" => \$INCLUDE_FAILED,
  "vault-layout"   => \$VAULT,
  "workflow=s"     => \$WORKFLOW,
  "ci"             => \$CI,
) or die "failed to get options for @ARGV\n";

my $extension   = shift(@ARGV);
my $branch      = shift(@ARGV);
my $download_to = shift(@ARGV) || '.';

if ($HELP or not defined $branch) {
  usage();
}

if ($PRIME) {
  $REPO='opennms-prime';
}
$PROJECT_ROOT = $CIRCLECI_API_ROOT . '/project/gh/OpenNMS/' . $REPO;

if ($WORKFLOW) {
  $INCLUDE_FAILED = 1;
}

our @EXTENSIONS = ('deb', 'rpm', 'oci', 'json', 'tgz', 'tar.gz', 'xml', 'yaml', 'yml');
if ($extension ne 'all') {
  @EXTENSIONS = (split(',', $extension));
}

my $agent = LWP::UserAgent::Determined->new;
$agent->default_header('Accept', 'application/json');
$agent->ssl_opts(verify_hostname => 0);

# fallback retries
$agent->timing("10,30,90,180");
$agent->codes_to_determinate()->{429} = 1;

if (defined $API_TOKEN) {
  $agent->default_header('Circle-Token', $API_TOKEN);
}

my $url = $PROJECT_ROOT . '/tree/' . uri_escape($branch) . '?limit=100';
my $response = $agent->get($url);
die "Can't get $url: ", $response->status_line, "\n" unless $response->is_success;

my $json = JSON::PP->new->utf8()->relaxed();
my $decoded = $json->decode($response->decoded_content);

my $workspaces = {};
my $workflows = [];

sub toEpoch {
  my $datetime = shift;
  if (not defined $datetime) {
    print STDERR "WARNING: toEpoch() expected a value, but value is undefined.\n";
    return 0;
  }
  return DateTime::Format::ISO8601->parse_datetime($datetime)->epoch();
}

# sort newest to oldest
for my $entry (sort { toEpoch($b->{'start_time'}) - toEpoch($a->{'start_time'}) } @$decoded) {
  #print "Full entry:\n";
  #print Dumper($entry), "\n";

  my $build_num = $entry->{'build_num'};
  my $workflow_id = $entry->{'workflows'}->{'workflow_id'};
  my $workspace_id = $entry->{'workflows'}->{'workspace_id'};

  if (not defined $workspace_id) {
    print STDERR "WARNING: found a workflow without a workspace ID... not sure what to do.\n";
    print STDERR Dumper($entry), "\n";
    exit(1);
  }

  if (not exists $workspaces->{$workspace_id}) {
    $workspaces->{$workspace_id} = {
      id => $workspace_id,
      failed => 0,
      workflows => [],
      jobs => {},
    };
  }
  my $workspace = $workspaces->{$workspace_id};

  my $job_name = $entry->{'workflows'}->{'job_name'};
  my $workflow = {
    id => $workflow_id,
    workspace_id => $workspace_id,
    failed => 0,
    builds => {},
  };

  push(@$workflows, $workflow);
  push(@{$workspace->{'workflows'}}, $workflow);

  if ($entry->{'status'} eq 'failed') {
    $workflow->{'failed'} = 1;
  }

  if (not exists $workspace->{'jobs'}->{$job_name}) {
    if ($workflow->{'failed'}) {
      $workspace->{'failed'} = 1;
    }
    $workspace->{'jobs'}->{$job_name} = $build_num;
  }

  $workflow->{'builds'}->{$job_name} = $build_num;
}

sub get_filename_from_url {
  my $url = shift;

  my ($filename) = $url =~ /^.*\/([^\/]+)$/;
  return $filename;
}

sub url_matches {
  my $url = shift;
  my $filename = get_filename_from_url($url);

  my ($filepart, $ext);
  for my $try (@EXTENSIONS) {
    my $quoted = quotemeta($try);
    if ($filename =~ qr(^(.*)\.${quoted}$)) {
      $filepart = $1;
      $ext = $try;
    }
    if (defined $filepart and defined $ext) {
      if (grep { $_ eq $ext } @EXTENSIONS) {
        if (defined $MATCH) {
          my $quoted = quotemeta($MATCH);
          if ($filepart =~ /${quoted}/i) {
            # print "${filename} matches \"$MATCH\", extension \"${ext}\". Downloading.\n";
            return 1;
          }
        } else {
          # print "${filename} matches extension \"${ext}\". Downloading.\n";
          return 1;
        }
      }
    }
  }

  # print "${filename} does not match --match=\"${MATCH}\", extensions=\"@{EXTENSIONS}\". Skipping.\n";
  return 0;
}

sub get_artifacts_for_workflow {
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

sub get_matching_artifacts_for_workspace_id {
  my $workspace_id = shift;
  my $workspace = $workspaces->{$workspace_id};
  if (not defined $workspace) {
    print STDERR "ERROR: unable to get workflows for workspace $workspace_id\n";
    exit(1);
  }

  my $artifacts = {};

  for my $workflow (@{$workspace->{'workflows'}}) {
    # print "workflow:", Dumper($workflow), "\n";
    my $ret = get_artifacts_for_workflow($workflow);
    # print "artifacts:", Dumper($ret), "\n";
    for my $key (keys %{$ret}) {
      for my $url (@{$ret->{$key}}) {
        my $filename = get_filename_from_url($url);
        if ($artifacts->{$filename}) {
          # print "already matched from a previous workflow: ", $filename, "\n";
          next;
        }
        if (url_matches($url)) {
          $artifacts->{$filename} = $url;
        }
      }
    }
  }

  # print "matched artifacts: ", Dumper($artifacts), "\n";

  return $artifacts;
}

sub download_artifact {
  my $url = shift;
  my $filename = get_filename_from_url($url);

  my $output_dir = $download_to;
  if ($VAULT) {
    for my $check (@$VAULT_MAPPING) {
      if ($filename =~ $check->[0]) {
        $output_dir = File::Spec->catdir($output_dir, $check->[1]);
        last;
      }
    }
  }

  if (not -d $output_dir) {
    make_path($output_dir);
  }

  my $output_file = File::Spec->catfile($output_dir, $filename);
  my $dl_string = "downloading to ${output_file}...";
  print $dl_string;
  if ($CI) {
    print "\n";
  }
  my $FILEOUT_HANDLE;
  open($FILEOUT_HANDLE, '>', $output_file) or die "\ncannot open $output_file for writing: $!\n";
  binmode $FILEOUT_HANDLE;
  my $amount = 0;
  my $last_time = 0;
  my $request = HTTP::Request->new(GET => $url);

  my $request_callback = sub {
    my ($data, $response, $protocol) = @_;
    $amount += length($data);

    my $time = time();
    if ($time != $last_time) {
      $last_time = $time;
      my $mb = scalar($amount / 1024 / 1024);
      if (not $CI) {
        printf "\r\%s \%.1fMB", $dl_string, $mb;
      }
    }

    print $FILEOUT_HANDLE $data;
  };
  my $dl_response = $agent->request($request, $request_callback, 1024 * 64);
  while ($dl_response->code == 429) {
    print "\r\e[K$dl_string retrying... ";
    my $wait = $dl_response->header('Retry-After');
    if ($wait) {
      if ($wait !~ /^\d+$/) {
        $wait = HTTP::Date::str2time($wait) - time();
      }
    } else {
      $wait = $WAIT_TIME;
      $WAIT_TIME = int(($WAIT_TIME * 1.3) + 0.5);
    }
    sleep($wait);
    $dl_response = $agent->request($request, $request_callback, 1024 * 64);
  }
  close($FILEOUT_HANDLE);
  if (not $dl_response->is_success) {
    unlink($output_file);
    die " failed: ", $dl_response->status_line, "\n";
  }
  if ($CI) {
    print "finished downloading ${output_file}\n";
  } else {
    print "\r\e[K$dl_string done\n";
  }
}

for my $workflow (@$workflows) {
  my $id = $workflow->{'id'};
  if ($WORKFLOW) {
    if ($id ne $WORKFLOW) {
      next;
    } else {
      print "Found workflow ${WORKFLOW}.\n";
    }
  }

  my $workspace = $workspaces->{$workflow->{'workspace_id'}};

  if (not $INCLUDE_FAILED and $workspace->{'failed'}) {
    print "WARNING: Workflow ", $id, ": workspace failed. Skipping.\n";
    next;
  }

  my $artifacts = get_matching_artifacts_for_workspace_id($workspace->{'id'});
  if ((keys %$artifacts) < 1) {
    print "WARNING: workspace for workflow ", $id, " passed, but does not contain any artifacts. Skipping.\n";
    next;
  }

  # print "Downloading all matching artifacts: ", Dumper($artifacts), "\n";
  for my $filename (keys %$artifacts) {
    my $url = $artifacts->{$filename};
    download_artifact($url);
  }

  exit(0);
}
