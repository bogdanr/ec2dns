#!/bin/bash
#
# Author:       Bogdan Radulescu <bogdan@nimblex.net>

START=`date +%s`

Warning() {
  echo -e "\e[31m Warning: \e[39m$@"
}

Info() {
  echo -e "\e[32m Info: \e[39m$@"
}


while getopts ":c:" opt; do
  case $opt in
    c)
      CONF=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG"
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument."
      exit 1
      ;;
  esac
done

if [[ $CONF ]]; then
  Info "we'll use $CONF for settings"
elif [[ -f ec2dns.conf ]]; then
  CONF=ec2dns.conf
elif [[ -f /etc/ec2dns.conf ]]; then
  CONF=/etc/ec2dns.conf
else
  Warning "ec2dns.conf was not found in the $PWD directory or in /etc"
  Info "You can copy the sample to /etc/ec2dns.conf and adjust it accordingly"
  exit
fi

# Set Environment Variables
. $CONF

# Sanity checks
command -v aws >/dev/null 2>&1          || { echo >&2 "AWS CLI Tools were not detected. Make sure you can run aws in the command line."; exit 1; }

grep $DOMAIN /etc/named.conf >/dev/null
if [[ $? != 0 ]]; then
    Warning $DOMAIN was not found in /etc/named.conf
    Info we will stop here
    exit 1
fi

if [[ ! -f /etc/named/nsupdate.key ]]; then
    Warning the nsupdate.key file is missing so you will not be able to add entries
    exit 1
fi

# REGIONS=(`aws ec2 describe-regions --output=text | awk '{print $3}'`)

rm -r /tmp/describe_instances

for PROFILE in ${PROFILES[*]}; do
  aws ec2 describe-instances --profile=$PROFILE --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,PrivateDnsName,PublicIpAddress,PublicDnsName,Tags[0].Value]' --output=text >> /tmp/describe_instances
done

createClean() {
/sbin/service named stop

rm -f $ZoneDir/${DOMAIN}*

echo "
\$ORIGIN ${DOMAIN}.
\$TTL 600        ; 10 minutes
$DOMAIN.           IN SOA  nboffice.${DOMAIN}. hostmaster.${DOMAIN}. (
                                `date \"+%Y%m%d\"`00 ; serial
                                2H    ; refresh
                                1H    ; retry
                                1W    ; expire
                                1D    ; minimum
                                )
                        NS      nboffice
                        A       `curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
nboffice                A       `curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
" > $ZoneDir/$DOMAIN

echo $STATIC >> $ZoneDir/$DOMAIN

/usr/sbin/named-checkzone $DOMAIN $ZoneDir/$DOMAIN
if [[ $? != 0 ]]; then
    Warning Zone $DOMAIN failed checks. BIND will not start!
    exit 1
fi

/sbin/service named start

}

createCMD() {
  while read line; do
      echo $line | awk -v domain=$DOMAIN '{print "update add "$6$7$8"."domain" 300 A " $2}' 
  done < /tmp/describe_instances
  echo send
}

createClean

# Obviously is pointless to add entries with nsupdate since we are already
# stopping the server all the time and installing a clean zone. We are keeping
# this in order to keep it as the only option in the future.

createCMD | /usr/bin/nsupdate -k /etc/named/nsupdate.key
