#!/bin/bash

create() {
  hal config provider kubernetes enable
  CONTEXT=$(kubectl config current-context)
  echo $CONTEXT

  hal config provider kubernetes account add prod --provider-version v2 --context $CONTEXT
  hal config features edit --artifacts true

  ADDRESS=index.docker.io
  REPOSITORIES=dgunjetti/hashfab-api
  USERNAME=dgunjetti
  PASSWORD_FILE=../dp

  hal config provider docker-registry account add dgunjetti \
    --address $ADDRESS \
    --username $USERNAME \
    --password-file $PASSWORD_FILE \
    --repositories $REPOSITORIES

  hal config provider docker-registry enable

  TOKEN_FILE=../git-token
  ARTIFACT_ACCOUNT_NAME=dgunjetti
  hal config artifact github account add $ARTIFACT_ACCOUNT_NAME --username dgunjetti --token-file $TOKEN_FILE
  
  hal config artifact github enable

  hal config deploy edit --type distributed --account-name prod  

  AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
  AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
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
  hal config artifact github account delete dgunjetti
  hal config provider docker-registry account delete dgunjetti
  hal deploy clean
  hal config provider kubernetes account delete prod 
}

if [ $# != 1 ]; then
  echo "usage: hal.sh <create/delete>"
fi

if [ "$1" = "create" ]; then
  create
elif [ "$1" = "delete" ]; then
  delete
fi


