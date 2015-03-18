# zdb tools

Scripts in this directory are used to export data from Zenoss
and reimport it into a sql database, where it can be accessed
using traditional SQL query. 

zdb_zen_to_mysql_base copies over most of the device-related
data. It is meant to be run in cron periodically. Takes about
1 minute per 1000 devices in my environment.

zdb_zen_to_mysql_slow copies over device attributes such as 
IP address, filesystem, etc. This takes much longer to run
because of the extra API calls per device. It is meant to 
be run in cron once per day or so.

json_list_hosts is an example script to interact with this 
database.

zdb.createtables.sql will create the tables required by the
copy scripts.
