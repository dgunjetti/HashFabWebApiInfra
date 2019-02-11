#!/bin/bash

create() {
  kubectl create -f jenkins/docker-secret.yaml

  kubectl create -f jenkins/jenkins-casc-config.yaml

  helm install stable/jenkins -n jenkins -f jenkins/values.yaml
}

delete() {
  helm delete jenkins 
  helm del --purge jenkins
}


if [ $# != 1 ]; then
  echo "usage: jenkins.sh <create/delete>"
fi

if [ "$1" = "create" ]; then
  create
elif [ "$1" = "delete" ]; then
  delete
fi

