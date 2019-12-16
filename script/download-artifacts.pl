#!/usr/bin/perl -w

use strict;
use warnings;

$|++;

use File::Path qw(make_path);
use File::Spec;
use HTTP::Request;
use JSON::PP qw();
use LWP;
use URI::Escape;

use vars qw(
  $CIRCLECI_API_ROOT
  $PROJECT_ROOT
);

$CIRCLECI_API_ROOT = 'https://circleci.com/api/v1.1';
$PROJECT_ROOT = $CIRCLECI_API_ROOT . '/project/gh/OpenNMS/opennms';

my $product     = shift(@ARGV);
my $package     = shift(@ARGV);
my $branch      = shift(@ARGV);
my $download_to = shift(@ARGV) || '.';

if (not defined $branch) {
  print "usage: $0 <horizon|minion|sentinel> <rpm|deb|oci> <branch> [download-directory]\n\n";
  exit(1);
}

my $agent = LWP::UserAgent->new;
$agent->default_header('Accept', 'application/json');
$agent->ssl_opts(verify_hostname => 0);

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

for my $workflow (@$workflows) {
  my $job = join('-', $product, ($package eq 'oci' ? 'rpm' : $package), 'build');

  if (not $workflow->{'failed'} and exists $workflow->{'builds'}->{$job}) {
    my $build_num = $workflow->{'builds'}->{$job};

    my $artifacts_response = $agent->get($PROJECT_ROOT . '/' . $build_num . '/artifacts');
    die "Can't list artifacts for job $job: ", $artifacts_response->status_line, "\n" unless $artifacts_response->is_success;

    my $artifacts = $json->decode($artifacts_response->decoded_content);
    @$artifacts = grep { /\.$package$/ } map { $_->{'url'} } @$artifacts;

    if (! -d $download_to) {
      make_path($download_to);
    }

    for my $artifact (@$artifacts) {
      my ($filename) = $artifact =~ /^.*\/([^\/]+)$/;
      my $output_file = File::Spec->catfile($download_to, $filename);

      my $dl_string = "downloading $filename...";
      print $dl_string;
      open FILEOUT, '>>', $output_file or die "\ncannot open $output_file for writing: $!\n";
      binmode FILEOUT;
      my $amount = 0;
      my $last_time = 0;
      my $request = HTTP::Request->new(GET => $artifact);
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

    exit(0);
  }

}

print "Failed to find passing job with artifacts.\n";
