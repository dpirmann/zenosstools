#!/usr/bin/perl

#=============================================================================
# zapi_toolkit.pl
#
# By David Pirmann. This script is an interface to the JSON API exposed by the
# "Zenoss Core" product from www.zenoss.org. 
# This script and others from https://github.com/dpirmann/zenosstools
# See README and the project WIKI on above GITHUB site for more details.
#
# This script is hereby released under GNU General Public License version 2
# See http://www.gnu.org/licenses/gpl-2.0.html for details.
#=============================================================================

#requirements - 
# * unix utility "curl"
# * Perl module JSON::Parse
#set up
# * edit "ZENBASE", "ZAPIUSER", and "ZAPIPASS" vars.

#zapiuser/zapipass - user/pass to use the zenoss api.
my $ZAPIUSER = 'apiuser';
my $ZAPIPASS = 'zapiuser';

#zenbase is the URL to your zenoss implementation
my $ZENBASE  = "http://$ZAPIUSER:$ZAPIPASS\@zenoss:8080";

package zapi_toolkit;
use JSON::Parse ':all';
use Data::Dumper;
use LWP::UserAgent;

#=============================================================================
# Function ZCURLPOST
# Invokes the curl post JSON api method
# zcurlpost <endpoint> <action> <method> <data>
# uses ZENBASE, ZAPIUSER, and ZAPIPASS variables
#=============================================================================
sub zcurlpost {
    my ($ROUTER_ENDPOINT,$ROUTER_ACTION,$ROUTER_METHOD,$DATA) = @_;

    my $server_endpoint = "$ZENBASE/zport/dmd/$ROUTER_ENDPOINT";
    my $post_data = qq({"action":"$ROUTER_ACTION","method":"$ROUTER_METHOD","data":[$DATA],"tid":1});

    # create request, and set custom HTTP request header fields
    my $req = HTTP::Request->new(POST => $server_endpoint);
    $req->header('content-type' => 'application/json');
    $req->content($post_data);

    # create connection and send over request
    # the ssl options are in case you're running Zenoss 5 which has a self signed cert by default
    my $ua = LWP::UserAgent->new(ssl_opts => {SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
					      verify_hostname => 0, });
    push @{ $ua->requests_redirectable }, 'POST'; #follow 302 and other redirect

    my $resp = $ua->request($req);

    if ($resp->is_success) {
	my $message = $resp->decoded_content;
	#print "Received reply: $message\n";
	return ($message);
    }
    else {
	print "HTTP POST error code: ", $resp->code, "\n";
	print "HTTP POST error message: ", $resp->message, "\n";
	die;
    }

}

#=============================================================================
# Function ZCURLGET
# Invokes the curl get JSON api method
# zcurlget <uid_path> <method> <data>
# uses ZENBASE, ZAPIUSER, and ZAPIPASS variables
#=============================================================================

sub zcurlget {
    my ($UIDPATH,$ROUTER_METHOD,$DATA) = @_;

    $UIDPATH=~s/\ /%20/g;

    #zenoss5 runs under a self signed SSL cert (https) by default;
    #so unless you have installed a real cert, ignore the warning
    my $ins;
    if ($ZENBASE =~ /^https/) {
        $ins=" --insecure "; #
    }

    my $cmd = qq(curl $ins -s -u "$ZAPIUSER:$ZAPIPASS" "${ZENBASE}${UIDPATH}/${ROUTER_METHOD}?${DATA}");
    return qx($cmd);
}

#=============================================================================
# Function CATCHERRORS
# Give it an $output from a json curl command and it will look through for
# the error codes errorType and errorValue
#=============================================================================
sub catchErrors {
    my ($output) = @_;

#some types of plain text errors found here.
#<input type="hidden" name="errorType" value="&lt;class 'Products.ZenModel.Exceptions.DeviceExistsError'&gt;" />
#<input type="hidden" name="errorValue" value="Device already exists with id" />
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
#
# not all API calls return json on success/error. some that do:
# setInfo
#=============================================================================
sub catchJsonErrors {
    my ($output) = @_;
    my $parsed= parse_json($output);
    my $success=%$parsed->{'result'}->{'success'};

    if ($success==0) {
	my $err=%$parsed->{'result'}->{'msg'};
        return (1, "Error, $err");
    }
    return 0;
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
    if ($val eq &zapi_toolkit::dec2ip(&zapi_toolkit::ip2dec($val))) {
	print STDERR "GETHOSTUID Found IP $val\n" if ($debug);
	$param= qq("ipAddress":"$val");
    } else {
	print STDERR "GETHOSTUID Found HOSTNAME $val\n" if ($debug);
	$param= qq("name":"$val");
    }

    my $data = qq({"params":{$param}});
    my $output = &zapi_toolkit::zcurlpost("device_router","DeviceRouter","getDevices",$data);
    warn if &zapi_toolkit::catchErrors($output);

    my $parsed= parse_json($output);
    print STDERR Dumper($parsed) if ($debug);

    my $total = %$parsed->{'result'}->{'totalCount'};
    print STDERR "GETHOSTUID TOTAL RESULTS = $total\n" if ($debug);

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
# urlencode/urldecode - implement url-encoding for curl arguments
#=============================================================================
sub urlencode {
    my $s = shift;
    $s =~ s/ /+/g;
    $s =~ s/([^A-Za-z0-9\+-])/sprintf("%%%02X", ord($1))/seg;
    return $s;
}

sub urldecode {
    my $s = shift;
    $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
    $s =~ s/\+/ /g;
    return $s;
}

#=============================================================================
# sub getCollectorList
# return an array of valid collector names
# should be combined into get_valid_values?
#=============================================================================
sub getCollectorList {
    my @collectors;
    my $data=qq({});
    my $output = &zapi_toolkit::zcurlpost("device_router","DeviceRouter","getCollectors",$data);
    my $parsed= parse_json($output);
    my $ct=@{%$parsed->{'result'}}; #number of groups
    for (my $gn=0;$gn<$ct;$gn++) {
	push @collectors, %$parsed->{'result'}[$gn];
    }
    return @collectors;
}

#=============================================================================
# sub get_valid_values 
# returns a list of valid values for:
# getProductionStates, getPriorities, getDeviceClasses, getGroups, getSystems, getAlertStates
#=============================================================================
sub get_valid_values {
    my ($type) = @_;

    die "Type must be one of getProductionStates|getPriorities|getDeviceClasses|getGroups|getSystems|getAlertStates\n"
	unless ($type =~ /^(getProductionStates|getPriorities|getDeviceClasses|getGroups|getSystems|getAlertStates)$/);

#these two come back with name/value pairs
#   perl json_wrapper post "device_router" "DeviceRouter" "getProductionStates" "{}"
#   perl json_wrapper post "device_router" "DeviceRouter" "getPriorities" "{}"
    
#this one just names names
#   perl json_wrapper post "device_router" "DeviceRouter" "getDeviceClasses" "{}"
#   perl json_wrapper post "device_router" "DeviceRouter" "getGroups" "{}"
#   perl json_wrapper post "device_router" "DeviceRouter" "getSystems" "{}"

    my $resfield;
    if ($type =~ /^(getProductionStates|getPriorities)$/) {
	$resfield='data';
    } elsif ($type eq "getDeviceClasses") {
	$resfield='deviceClasses';
    } elsif ($type eq "getGroups") {
	$resfield='groups';
    } elsif ($type eq "getSystems") {
	$resfield='systems';
    } elsif ($type eq "getAlertStates") {
        my %alertstates=('new', 0, 'acknowledged', 1, 'suppressed', 2, 'closed', 3, 'cleared', 4, 'aged', 6);
        return %alertstates;
    }

    my $output = &zapi_toolkit::zcurlpost("device_router","DeviceRouter","$type");
    my $parsed= parse_json($output);
    my $total=@{%$parsed->{'result'}->{$resfield}};

    my %valarry;
    for (my $i=0;$i<$total;$i++) {
	my $value=1;
        if (defined (%$parsed->{'result'}->{$resfield}[$i]->{'value'})) {
	    $value = %$parsed->{'result'}->{$resfield}[$i]->{'value'};
	}
        my $name  = %$parsed->{'result'}->{$resfield}[$i]->{'name'};
	$valarry{$name}=$value;
    }
    return %valarry;
}
#Examples:
#$prodstatevalue{'1000'}='Production';
#$prodstatevalue{'500'}='Pre-Production';
#$prodstatevalue{'400'}='Test';
#$prodstatevalue{'300'}='Maintenance';
#$prodstatevalue{'-1'}='Decommissioned';
#$priovalue{'5'}='Highest';
#$priovalue{'4'}='High';
#$priovalue{'3'}='Normal';
#$priovalue{'2'}='Low';
#$priovalue{'1'}='Lowest';
#$priovalue{'0'}='Trivial';

#=============================================================================
# Function RENAMEHOST
# renames a host $hostpath to new name $newname
#=============================================================================
sub renamehost {
    my ($newname,$hostpath) = @_;

    my $output=&zapi_toolkit::zcurlget($hostpath,"renameDevice","newId=$newname");
    return $output;
}

#=============================================================================
# Function GETINFOKEY
# Give it an hostpath and it returns an array of device getInfo props
# (and also cProps)
#=============================================================================

sub getinfokey {
    my ($hostpath) = @_;

    my %keyarray;

    #first part, getInfo
    my $data = qq({"uid":"$hostpath"});
    my $output = &zapi_toolkit::zcurlpost("device_router","DeviceRouter","getInfo",$data);
    my $parsed= parse_json($output);

    %keyarray=&zapi_toolkit::recurseParse("",$parsed->{result}->{data},%keyarray);

    #added this little bit to include a device's custom properties into the array
    my $output=&zapi_toolkit::zcurlget($hostpath,"deviceCustomEdit","");
    %keyarray=&zapi_toolkit::parsecprop($output,%keyarray);

    return %keyarray;
}

#=============================================================================
#sub recurseParse
#recursively traverses a json_parsed hash of hashes etc and returns
#a %keyarray hash of key-value pairs
#=============================================================================
sub recurseParse {
    my ($name,$parsed,%keyarray) = @_;

    foreach (sort keys %$parsed) {
	if (ref(%$parsed->{$_}) eq "HASH") {
	    %keyarray=&zapi_toolkit::recurseParse("$name/$_",$parsed->{$_},%keyarray);
	} elsif (ref(%$parsed->{$_}) eq "ARRAY") {
            # must figure out how many elements there are in the array, and then iterate 
	    # this kind of sucks because the keys need to have the array index in them
	    # to keep them unique. How else to do it.... not sure.
	    my $ct=@{%$parsed->{$_}}; #number of groups
	    for (my $gn=0;$gn<$ct;$gn++) {
		if (ref(%$parsed->{$_}[$gn]) eq "HASH") {
                    %keyarray=&zapi_toolkit::recurseParse("$name/$gn/$_",$parsed->{$_}[$gn],%keyarray);
                } else {
                    $keyarray{"$name/$_"}=$parsed->{$_}[$gn] . "," . $keyarray{"$name/$_"};
                }
	    }
	    $keyarray{"$name/$_"} =~ s/,$//;

	} else {
	    $keyarray{"$name/$_"}=%$parsed->{$_};
	}
    }
    return %keyarray;
}

#=============================================================================
# Function PARSECPROP
# takes the output of the curl get deviceCustomEdit html page and
# returns a hash of the cprops {variable/type} = value
#=============================================================================
sub parsecprop {
    my ($output,%aar) = @_;

#<input class="tablevalues" type="text" size="50" name="cWindowsDomainName:string" value="" />
#<input class="tablevalues" type="text" size="50" name="cDateTest:date" value="1900/01/01 00:00:00 US/Central" />

    my @lines = split /\n/, $output;
    foreach my $line (@lines) {
	if ($line =~ /input class="tablevalues"/) {
	    my ($name) = ($line =~ /name=\"(.+?)\"/);
	    my ($value) = ($line =~ /value=\"(.+?)\"/);
	    $aar{"/$name"}=$value;
	}
    }
    return %aar;
}

#=============================================================================
# Function MANIP_EVENT
# Takes an event id and action and uses curlpost to hit the eventsrouter
# manip_event <task> <eventid>
# where task is 'close', 'reopen', 'acknowledge', 'unacknowledge'
#=============================================================================
sub manip_event {
    my ($task, $evid) = @_;

    die unless ($task =~ /^(close|reopen|acknowledge|unacknowledge|detail)$/);

    if ($evid =~ /\/evid:/) {
	$evid =~ s/\/evid:\s*//;
    }

    my $data;

    if ($task eq 'detail') {
	$data=qq({"evid":"$evid"});
    } else {
	$data=qq({"evids":["$evid"]});
    }

    my $output = &zapi_toolkit::zcurlpost("evconsole_router","EventsRouter","$task",$data);

    my $parsed= parse_json($output);

    if ($task eq 'detail') {
	%keyarray=&zapi_toolkit::recurseParse("",$parsed->{result}->{event}[0],%keyarray);
	foreach (sort keys %keyarray) {
	    print "$_ : $keyarray{$_}\n";
	}

    } else {
        if (%$parsed->{'result'}->{'data'}->{'updated'} < 1) {
	    print STDERR "No events modified.... maybe incorrect evid or already in state specified\n";
	    exit;
	} else {
	    if (%$parsed->{'result'}->{'success'}) {
		print STDERR "Success\n";
	    } else {
		print STDERR "Failure\n";
	    }
	}
    }
}

#=============================================================================
# Function SETCPROP
# Invokes the curl post JSON api method
# setcprop <endpoint> <action> <method> <data>
# uses ZENBASE, ZAPIUSER, and ZAPIPASS variables
#=============================================================================
sub setcprop {
    my ($hostpath,$cprop,$cvalue) = @_;

    if ($debug) {
	print "Hostpath=$hostpath\n";
	print "Cprop=$cprop\n";
	print "Cvalue=$cvalue\n";
    }

    #first, get existing cprops... we need to make sure it exists and is string type...

    my $output=&zapi_toolkit::zcurlget($hostpath,"deviceCustomEdit","");
    &zapi_toolkit::catchErrors($output);
    my %aar=&zapi_toolkit::parsecprop($output);

    if (exists ($aar{$cprop})) {
	print "We may proceed.\n" if ($debug);
    } else {
	die "Did not exist...\n";
    }
    
    if ($cprop=~/\:string/) {
	print "We may proceed.\n" if ($debug);
    } else {
	die "Not string...\n";
    }

    $cprop=~ s/\:/%3A/;#urlencode it
    $cprop=~ s|^/||; #cprops come back from parsecprop as properties in a tree-- strip the leading /

    #only for string type properties!!!
    $cvalue=&zapi_toolkit::urlencode($cvalue);

    my $ins;
    if ($ZENBASE =~ /^https/) {
        $ins=" --insecure ";
    }

    #this could probably be converted to work with zapi_toolkit::zcurlget with some testing
    my $cmd = qq(curl $ins -s -u "$ZAPIUSER:$ZAPIPASS" -X POST -H "Content-Type: application/x-www-form-urlencoded" \\
    -d "zenScreenName=deviceCustomEdit" \\
    -d "${cprop}=${cvalue}" \\
    -d "saveCustProperties%3Amethod=+Save+" \\
    "${ZENBASE}${hostpath}");

    return qx($cmd);
}

#=============================================================================
# Function CREATEMWINDOW
# Given a maintenance window name and a Zenoss device name, creates the maint window
#=============================================================================

sub createmwindow {
    my ($MWNAME,$hostpath) = @_;
    my $output=&zapi_toolkit::zcurlget($hostpath,"manage_addMaintenanceWindow","newId=$MWNAME");
    return $output;
}

#=============================================================================
# Function MODIFYMWINDOW
# modifymwindow MWname, hostpath, time(length in minutes)
# sets up a MW on host starting NOW for given length of time (in minutes)
#=============================================================================

sub modifymwindow {
    my ($MWNAME,$hostpath,$time) = @_;
    
    #today's current date and time will be used to start the Mwindow immediately
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());
    $year=$year+1900;
    $mon=$mon+1;

    #the supplied # of minutes converted into hours and minutes
    my $dhours = int ($time / 60);
    my $dminut = int ($time % 60);

    my $output=&zapi_toolkit::zcurlget($hostpath,"maintenanceWindows/$MWNAME/manage_editMaintenanceWindow","startHours=${hour}&startMinutes=${min}&durationHours=${dhours}&durationMinutes=${dminut}&startDate=${mon}/${mday}/${year}&repeat=Never&enabled=1");

    return $output;
}



#=============================================================================
# sub zcurlreport
# given some options and a report type, curl it out...
#=============================================================================
sub zcurlreport {
    my ($report_type,$options) = @_;

    $options=~ s/^\n//g; #remove leading
    $options=~ s/\n$//g; #..and trailing carriage returns in case any were present

    $debug=0;

    my $ins;
    if ($ZENBASE =~ /^https/) {
        $ins=" --insecure ";
    }

    my $cmd = qq(curl $ins -s -u "$ZAPIUSER:$ZAPIPASS" -X POST $options "$ZENBASE/zport/dmd/Reports/$report_type");

    print STDERR "zcurlreport value of report_type=\n$report_type\n--\n" if ($debug);
    print STDERR "zcurlreport value of options=\n$options\n--\n" if ($debug);
    print STDERR "zcurlreport value of CMD=\n$cmd\n--\n" if ($debug);

    my $output = qx($cmd);

    return $output;

}


#=============================================================================
#sub lastmonthsdate 
#returns a string containing the date of the first of last month in form 11/1/2014
#=============================================================================
sub lastmonthsdate {
    #first find current date...
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());

    #year from localtime is years since 1900
    $year=$year+1900;

    #mon from localtime is range 0..11
    $mon=$mon+1;

    if ($mon==1) { 
	$mon=12;
	$year=$year-1;  #last year
    } else {
	$mon=$mon-1;
    }
    return "$mon/1/$year";
}

#=============================================================================
#sub lastmonthedate 
#returns a string containing the date of the last day of last month in form 11/30/2014
#=============================================================================
sub lastmonthedate {
    use DateTime;
    #first find current date...
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());

    #year from localtime is years since 1900
    $year=$year+1900;

    #mon from localtime is range 0..11
    $mon=$mon+1;

    if ($mon==1) { 
	$mon=12;
	$year=$year-1;  #last year
    } else {
	$mon=$mon-1;
    }

    my $date = DateTime->new(
	year  =>  $year,
	month => $mon,
	);

    my $date2 = DateTime->last_day_of_month(  
	year  =>  $date->year,
	month => $date->month,
	);

    return $date2->mdy('/');
}

