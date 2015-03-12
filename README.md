# welcome to dpirmann's zenoss tools repo

requirements -
 * unix utility "curl"
 * Perl module JSON::Parse

----------------------------------------------------------------------

zapi_toolkit.pl - includes a bunch of subroutines useful for
interacting with the Zenoss JSON API. Every other tool in this repo
will depend on the zapi_toolkit.

to set up
 * edit "ZENBASE", "ZAPIUSER", and "ZAPIPASS" vars.

----------------------------------------------------------------------

pzenoss_api - example script to call Zenoss JSON API router methods.
It is a perl reimplemation of an existing bash zenoss_api script.
See http://wiki.zenoss.org/Working_with_the_JSON_API for more examples.

Syntax: pzenoss_api "endpoint" "action" "method" "data"

Examples:

perl pzenoss_api "device_router" "DeviceRouter" "getProductionStates" "{}"

----------------------------------------------------------------------




