#!/bin/bash

create() {
  hal config provider kubernetes enable
  CONTEXT=$(kubectl config current-context)
  echo $CONTEXT
  ACCOUNT=hashfab
  hal config provider kubernetes account add $ACCOUNT --provider-version v2 --context $CONTEXT
  hal config features edit --artifacts true

  ADDRESS=index.docker.io
  REPOSITORIES=dgunjetti/hashfab-api
  USERNAME=dgunjetti
  PASSWORD_FILE=dp

  hal config provider docker-registry account add dgunjetti \
    --address $ADDRESS \
    --username $USERNAME \
    --password-file $PASSWORD_FILE \
    --repositories $REPOSITORIES

  hal config provider docker-registry enable

  export TOKEN_FILE=git-token
  export ARTIFACT_ACCOUNT_NAME=dgunjetti
  hal config artifact github account add $ARTIFACT_ACCOUNT_NAME --username dgunjetti --token-file $TOKEN_FILE
  
  hal config provider git enable

  hal config deploy edit --type distributed --account-name $ACCOUNT  

  export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
  export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
  echo $AWS_SECRET_ACCESS_KEY | hal config storage s3 edit --access-key-id $AWS_ACCESS_KEY_ID \
    --secret-access-key --region ap-south-1

  hal config storage edit --type s3

  hal config version edit --version 1.11.7

  hal deploy apply
  if [ $? != 0 ]; then 
    echo 'hal deploy failed'
    exit
  fi
}

delete() {
  hal deploy clean
}

if [ $# != 1 ]; then
  echo "usage: hal.sh <create/delete>"
fi

if [ "$1" = "create" ]; then
  create
elif [ "$1" = "delete" ]; then
  delete
fi


