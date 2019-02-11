#!/bin/sh

kubectl create -f helm/tiller.yaml

helm init --service-account tiller --upgrade

sleep 15

# helm install stable/nginx-ingress

# sleep 15

