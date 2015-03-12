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
