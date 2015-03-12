#!/usr/bin/perl

#requirements - 
# * unix utility "curl"
# * Perl module JSON::Parse
#set up
# * edit "ZENBASE", "ZAPIUSER", and "ZAPIPASS" vars.

#zenbase is the URL to your zenoss implementation
my $ZENBASE  = 'http://zenoss:8080';

#zapiuser/zapipass - user/pass to use the zenoss api.
my $ZAPIUSER = 'apiuser';
my $ZAPIPASS = 'zapiuser';

#=============================================================================
# Function ZCURLPOST
# Invokes the curl post JSON api method
# zcurlpost <endpoint> <action> <method> <data>
# uses ZENBASE, ZAPIUSER, and ZAPIPASS variables
#=============================================================================
package zapi_toolkit;
use JSON::Parse ':all';
use Data::Dumper;

sub zcurlpost {
    my ($ROUTER_ENDPOINT,$ROUTER_ACTION,$ROUTER_METHOD,$DATA) = @_;

    #all the quote marks inside the data string have to be escaped.
    #i do it here so that the methods that call zcurlpost are a little
    #easier to read

    $DATA=~s/\"/\\"/g;

    #in the cmd there's those end of line escaped backslashes to make the command
    #a little easier to read

    my $cmd = qq(curl -s -u "$ZAPIUSER:$ZAPIPASS" -X POST -H "Content-Type: application/json" \\
    -d "{\\"action\\":\\"$ROUTER_ACTION\\",\\"method\\":\\"$ROUTER_METHOD\\",\\"data\\":[$DATA], \\"tid\\":1}" \\
    "$ZENBASE/zport/dmd/$ROUTER_ENDPOINT");

    return qx($cmd);
}


#=============================================================================
# Function CATCHERRORS
# Give it an $output from a json curl command and it will look through for
# the error codes errorType and errorValue
#=============================================================================
sub catchErrors {
    my $subname=(caller(0))[3]; my $debugsub=1 if ($debuggy{$subname}==1);
    logger("Entering $subname") if ($debugsub);

    my ($output) = @_;

#some types of plain text errors found here.
#<input type="hidden" name="errorType" value="&lt;class 'Products.ZenModel.Exceptions.DeviceExistsError'&gt;" />
#<input type="hidden" name="errorValue" value="Device already exists with id mfrplxmontest01" />
#'error_formatted': 'Traceback (most recent call last):\n  File "/opt/zenoss/lib/python/ZPublisher/Publish.py", line 11'

    my $errorType; my $errorValue; my $errorFormatted;
    for (split /^/, $output) {
	if (/errorType/) {
	    ($errorType) = ($_ =~ /\"errorType\" value=\"(.+)\"/);
	    $errorType=~s/&[lg]t;//g;
	}
	if (/errorValue/) {
	    ($errorValue) = ($_ =~ /\"errorValue\" value=\"(.+)\"/);
	}
	if (/error_formatted/) {
	    ($errorFormatted) = ($_ =~ /'error_formatted':\ (.+)/);
	    $errorFormatted =~ s{\\n}{\012}g;
	}
    }

    if ($errorType || $errorValue || $errorFormatted) {
	print "An error has occured:\n";
	print $errorType || $errorValue || $errorFormatted;
	print "\n";
	return 1;
    }
    return 0;
}

#=============================================================================
# Function CATCHJSONERRORS
# Give it an $output from a json curl POST command and it will look through for
# the success and msg values.. returns value of success (0 for errors, 1 for ok)
#=============================================================================
sub catchJsonErrors {
    my ($output) = @_;
    my $parsed= parse_json($output);
    my $success=%$parsed->{'result'}->{'success'};

    if ($success==0) {
	my $err=%$parsed->{'result'}->{'msg'};
	print "Error, $err\n";
    }
    return $success;
}

#=============================================================================
# Function GETHOSTUID
# Given a Zenoss device name or managed IP, returns its /zport/dmd/host/path/uid
# returns UID if it matches, -1 if it found no matches, -2 if inexact matches
#=============================================================================

sub gethostuid {
    my ($val) = @_;

    

    #gethostuid can take either an IP address or host name to search on.
    #In order to figure out which we have, we'll convert the value to 
    #decimal and back to dotted - if there's a match it was an IP address.
    my $param; 
    if ($val eq zapi_toolkit::dec2ip(zapi_toolkit::ip2dec($val))) {
	print STDERR "GETHOSTUID Found IP $val\n" if ($debugsub);
	$param= qq("ipAddress":"$val");
    } else {
	print STDERR "GETHOSTUID Found HOSTNAME $val\n" if ($debugsub);
	$param= qq("name":"$val");
    }

    my $data = qq({"params":{$param}});
    my $output = zcurlpost("device_router","DeviceRouter","getDevices",$data);
    warn if &zapi_toolkit::catchErrors($output);

    my $parsed= parse_json($output);
    print STDERR Dumper($parsed) if ($debugsub);

    my $total = %$parsed->{'result'}->{'totalCount'};
    print STDERR "GETHOSTUID TOTAL RESULTS = $total\n" if ($debugsub);

    #return -1 if no results found
    if ($total == 0) {
	return -1;
    }

    for (my $i=0;$i<$total;$i++) {
	my $nn=%$parsed->{'result'}->{'devices'}[$i]->{'name'};
	my $ipa=%$parsed->{'result'}->{'devices'}[$i]->{'ipAddressString'};
	my $uid=%$parsed->{'result'}->{'devices'}[$i]->{'uid'};

	if ($param =~ /^\"name\"/) { # we searched by hostname - flag set above
	    if (uc($nn) eq uc($val)) {
		return $uid;
	    }
	} else { # we searched by ipaddress
	    if ($ipa eq $val) {
		return $uid;
	    }
	}
    } 
    
    #return -2 -- inexact match found to search query "$val"
    return -2;
}

#=============================================================================
# convert IP addresses from dec to dotted and v.v
#=============================================================================
# this sub converts a decimal IP to a dotted IP
sub dec2ip ($) { join '.', unpack 'C4', pack 'N', shift; }
 
# this sub converts a dotted IP to a decimal IP
sub ip2dec ($) { unpack N => pack CCCC => split /\./ => shift; }

#=============================================================================
# sub getCollectorList
# return an array of valid collector names
#=============================================================================
sub getCollectorList {
    my @collectors;
    my $data=qq({});
    my $output = ZenossPerl::zcurlpost("device_router","DeviceRouter","getCollectors",$data);
    my $parsed= parse_json($output);
    my $ct=@{%$parsed->{'result'}}; #number of groups
    for (my $gn=0;$gn<$ct;$gn++) {
	push @collectors, %$parsed->{'result'}[$gn];
    }
    return @collectors;
}
