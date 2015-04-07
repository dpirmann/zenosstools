#!/usr/bin/perl

#=============================================================================
# example_availability_report.pl

# By David Pirmann. This script is an interface to the JSON API exposed by the
# "Zenoss Core" product from www.zenoss.org. This script requires "zapi_toolkit" 
# from https://github.com/dpirmann/zenosstools
# See README and the project WIKI on above GITHUB site for more details.
#
# This script is hereby released under GNU General Public License version 2
# See http://www.gnu.org/licenses/gpl-2.0.html for details.
#=============================================================================

sub usage {
    print "Usage: $0 [-g group] [-s system]\n";
    print "Group and system names are Zenoss organizers.\n";
    print "E.g. group /zport/dmd/Groups/TESTGROUP,\n";
    print "and system /zport/dmd/Systems/TESTSYSTEM.\n";
    print "It will calculate first and last days of prior month for report period.\n";
    exit;
}

require 'zapi_toolkit.pl';

use Getopt::Std;

my $debug=1;

my %opts;
my $group;
my $system;
my %defs;

#----------------------------------------------------
# process the arguments
#----------------------------------------------------

getopts('g:s:h',\%opts);
if (defined $opts{'h'}) {
    &usage;
}

if (defined $opts{'g'}) {
    $group = $opts{'g'};
}

if (defined $opts{'s'}) {
    $system = $opts{'s'};
}

#----------------------------------------------------
# Calculate last month start-end dates
#----------------------------------------------------
my $sd=&zapi_toolkit::lastmonthsdate;
my $ed=&zapi_toolkit::lastmonthedate;

#----------------------------------------------------
# Assemble report options
#----------------------------------------------------

my $report_type="Performance%20Reports/Availability%20Report";

my @options;
push @options, qq(-d "DeviceClass=/Server");
push @options, qq(-d "System=$system") if ($system);
push @options, qq(-d "DeviceGroup=$group") if ($group);
push @options, qq(-d "Location=/");
push @options, qq(-d "device=");
push @options, qq(-d "severity=4");
push @options, qq(-d "startDate=$sd");
push @options, qq(-d "endDate=$ed");
push @options, qq(-d "eventClass=/Status/Ping");
push @options, qq(-d "generate=Generate");
push @options, qq(-d "doExport=export%20all");
my $options=join (' ',@options);

#----------------------------------------------------
#grab the report (it's a CSV)
#----------------------------------------------------
my $output=&zapi_toolkit::zcurlreport($report_type,$options);

print "$output\n";

exit;

