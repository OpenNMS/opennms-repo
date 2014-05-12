#!/usr/bin/perl -w

$|++;

use strict;
use warnings;

use OpenNMS::Release;
use version;

print version->new($OpenNMS::Release::VERSION);
