ec2dns
======

### Have the instance name automatically associated in DNS

ec2dns is a script which automatically adds entries in a DNS zone that you
define. The entries added are actually the name of the machines associated
with either the internal IP, external IP, internal DNS or external DNS.

ec2dns only updates BIND because route53 has limitations related to CNAMEs.

ec2dns requires aws cli tools and at least one profile defined in .aws/config
nsupdate must be working and the zone must be manually configured in named.conf

In the initial release only A records to internal IP addresses are implemented
