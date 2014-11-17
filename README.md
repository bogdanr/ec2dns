ec2route / ec2dns
======

### Have the instance name automatically added in route53 or BIND

ec2dns /ec2route is a script which automatically adds entries in a DNS zone
that you define. The entries added are actually the name of the machines
associated with the internal IP.

ec2dns was replaced by ec2route which now uses Route53 because support for
internal zones were added to Route53. ec2dns is still left in place for BIND.

ec2route and ec2dns requires aws cli tools and at least a profile in .aws/config

For ec2dns nsupdate must be working and the zone must be manually configured in named.conf

For ec2route the internal zone has to be created in route53 and the ZONEID should be specified in the script.

ec2route does not delete entries from Route53 in order to allow you to have custom records.
ec2route will create or update new and existing records which change.
