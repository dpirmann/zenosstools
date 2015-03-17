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

    #zenoss5 runs under a self signed SSL cert (https) by default;
    #so unless you have installed a real cert, ignore the warning
    my $ins;
    if ($ZENBASE =~ /^https/) {
        $ins=" --insecure "; #
    }

    my $cmd = qq(curl $ins -s -u "$ZAPIUSER:$ZAPIPASS" -X POST -H "Content-Type: application/json" \\
    -d "{\\"action\\":\\"$ROUTER_ACTION\\",\\"method\\":\\"$ROUTER_METHOD\\",\\"data\\":[$DATA], \\"tid\\":1}" \\
    "$ZENBASE/zport/dmd/$ROUTER_ENDPOINT");

    return qx($cmd);
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
    if ($val eq &zapi_toolkit::dec2ip(&zapi_toolkit::ip2dec($val))) {
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
# will return a list of valid values for getProductionStates, getPriorities, getDeviceClasses
#=============================================================================
sub get_valid_values {
    my ($type) = @_;

    die "Type must be one of getProductionStates|getPriorities|getDeviceClasses|getGroups|getSystems\n"
	unless ($type =~ /^(getProductionStates|getPriorities|getDeviceClasses|getGroups|getSystems)$/);

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
    my $output = zcurlpost("device_router","DeviceRouter","getInfo",$data);
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
    my $subname=(caller(0))[3]; my $debugsub=1 if ($debuggy{$subname}==1);
    logger("Entering $subname") if ($debugsub);

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
