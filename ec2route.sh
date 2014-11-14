#!/bin/bash
#
# This script is used to add tags for the resources associated to an instance
#
# Author: Bogdan Radulescu <bogdan@nimblex.net>

# Settings
#
# We need to define profiles and the ZONEID 
PROFILES=(bk-eu-west bk-us-west bk-us-east bk-ap-southeast)
ZONEID=ZNRVV81EPRU2
DOMAIN=netop.local.

# Check if we have jq
which jq >/dev/null
if [[ $? != "0" ]]; then
    if [[ `uname -m` = "x86_64" ]]; then
        wget -O /usr/local/bin/jq http://stedolan.github.io/jq/download/linux64/jq
    else
        wget -O /usr/local/bin/jq http://stedolan.github.io/jq/download/linux32/jq
    fi
    chmod +x /usr/local/bin/jq
fi



TMPFILE="/tmp/$$.tmp"

listRoute53() {
  aws route53 list-resource-record-sets --hosted-zone-id $ZONEID | jq '.ResourceRecordSets[] | select(.Type == "A") | {(.Name): .ResourceRecords[].Value}' -c
  aws route53 list-resource-record-sets --hosted-zone-id $ZONEID | jq '.ResourceRecordSets[] | select(.Type == "TXT") | {(.Name): .ResourceRecords[].Value}' -c
}

createJSON() {

LastChange="Changes done on `date`"
#  aws ec2 describe-instances --profile=$1 --filters "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PrivateIpAddress,Tags[?Key==`Name`] | [0].Value]' | jq '.[]' -c | \
  while read line; do
    InternalIP=`echo $line | awk -F "\"" '{print $2}'`
    RRSet=`echo $line | awk -F "\"" '{print tolower($4)}' | sed -e 's/ //g'`".$DOMAIN"
    if [[ ${RRSet} = ".${DOMAIN}" ]] || [[ -z ${InternalIP} ]]; then
        Unnamed+=1
        continue
    fi
    if grep -q "${RRSet}.*${InternalIP}" /tmp/route53entries; then
        echo -e ${RRSet} '\t' is OK
    elif grep -q "${RRSet}" /tmp/route53entries; then
        echo -e "${RRSet}" '\t' has a different IP
        JSON=$JSON"    { \"Action\": \"UPSERT\", \"ResourceRecordSet\": { \"Name\": \""${RRSet}"\", \"Type\": \"A\", \"TTL\": 600, \"ResourceRecords\": [ { \"Value\": \""${InternalIP}"\" } ] } },
"
        JSON=$JSON${JSONc}
    else
        echo -e ${RRSet} '\t' is new
        JSON=$JSON"    { \"Action\": \"CREATE\", \"ResourceRecordSet\": { \"Name\": \""${RRSet}"\", \"Type\": \"A\", \"TTL\": 600, \"ResourceRecords\": [ { \"Value\": \""${InternalIP}"\" } ] } },
"
    fi
  done < <(aws ec2 describe-instances --profile=$1 --filters "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PrivateIpAddress,Tags[?Key==`Name`] | [0].Value]' | jq '.[]' -c)

  if grep -q "lastchange" /tmp/route53entries; then
    JSONl="    { \"Action\": \"UPSERT\", \"ResourceRecordSet\": { \"Name\": \"lastchange.$DOMAIN\", \"Type\": \"TXT\", \"TTL\": 600, \"ResourceRecords\": [ { \"Value\": \"\\\"${LastChange}\\\"\" } ] } }"
  else  # We should go here only the first time the scrip is ran.
    JSONl="    { \"Action\": \"CREATE\", \"ResourceRecordSet\": { \"Name\": \"lastchange.$DOMAIN\", \"Type\": \"TXT\", \"TTL\": 600, \"ResourceRecords\": [ { \"Value\": \"\\\"${LastChange}\\\"\" } ] } }"
  fi


JSONs="{
  \"Comment\": \"The script which does this was finished on a friday :)\",
  \"Changes\": [
"$JSON$JSONl"
  ]
}"

  echo "$JSONs" > $TMPFILE

  if [[ ${Unnamed} -gt 0 ]]; then
    echo "We have $Unnamed instance(s) which don't have a name tag configured."
  fi
}

for PROFILE in ${PROFILES[*]}; do
#  processInstances $PROFILE >> /var/log/ec2route.log
  listRoute53 > /tmp/route53entries
  createJSON $PROFILE
done

cat $TMPFILE
aws route53 change-resource-record-sets --hosted-zone-id $ZONEID --change-batch file://$TMPFILE
unlink $TMPFILE

