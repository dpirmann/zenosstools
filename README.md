# welcome to dpirmann's zenoss tools repo

See https://github.com/dpirmann/zenosstools/wiki
for more documentation on the scripts in this github repo.

** UNOFFICIAL ** UNOFFICIAL ** UNOFFICIAL ** UNOFFICIAL ** UNOFFICIAL 

The scripts here are not provided by the Zenoss company or 
community support organization.  Use at your own risk.

** UNOFFICIAL ** UNOFFICIAL ** UNOFFICIAL ** UNOFFICIAL ** UNOFFICIAL 

General requirements -
 * unix utility "curl"
 * Perl module JSON::Parse

Start with pzenoss_api. This is an example script to call Zenoss JSON
API router methods.  It is a perl reimplemation of an existing bash
zenoss_api script from http://wiki.zenoss.org/Working_with_the_JSON_API 
It is standalone (does not require zapi_toolkit.pl or any other
scripts from this repo).  To set up, edit "ZENBASE",
"ZAPIUSER", and "ZAPIPASS" vars.

The zapi_toolkit.pl includes a bunch of subroutines useful for
interacting with the Zenoss JSON API. Every other tool in this repo
will depend on the zapi_toolkit. To set up, edit "ZENBASE",
"ZAPIUSER", and "ZAPIPASS" vars.


