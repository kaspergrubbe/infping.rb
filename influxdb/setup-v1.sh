#!/bin/bash
set -e

username=${USER_NAME}
password=${USER_PASS}
bucket_name=${USER_BUCKET}
org_id=$(influx org ls | awk 'NR==2 {print $1}') 
org_name=$(influx org ls | awk 'NR==2 {print $2}') 

influx bucket create \
  --name ${bucket_name} \
  --org-id ${org_id} \
  --retention 520w

influx user create \
  --name ${username} \
  --password ${password} \
  --org-id ${org_id}

bucket_list=$(influx bucket list --org-id ${org_id} --name ${bucket_name})
bucket_id=$(echo "$bucket_list" | awk 'NR==2 {print $1}')

influx auth create \
  --org-id ${org_id} \
  --user ${username} \
  --read-bucket ${bucket_id} \
  --write-annotations \
  --write-bucket ${bucket_id}

