#!/bin/bash

NAME="$2.hashfab.k8s.local"
BUCKET_NAME="$NAME"
REGION="ap-south-1"
ZONE1="ap-south-1a"
ZONE2="ap-south-1b"

create_kops_user() {
  aws iam create-group --group-name kops

  if [ $? == 0 ]; then
    aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess --group-name kops
    aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess --group-name kops
    aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --group-name kops
    aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/IAMFullAccess --group-name kops
    aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess --group-name kops

    aws iam create-user --user-name kops

    aws iam add-user-to-group --user-name kops --group-name kops

    aws iam create-access-key --user-name kops
    
    aws configure 
    aws iam list-users
  fi
  export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
  export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
}

create() {
  
  create_kops_user

  ssh-keygen -t rsa -f ~/.ssh/id_rsa -P $2
  if [ $? != 0 ]; then
    echo "ssh public key generation failed"
    exit
  fi

  aws s3api create-bucket \
    --bucket $BUCKET_NAME  \
    --region $REGION  \
    --create-bucket-configuration \
    LocationConstraint=$REGION
  if [ $? != 0 ]; then
      echo "create aws s3 bucket failed"
  fi

: <<'END'
  aws s3api put-bucket-versioning \
        --bucket $BUCKET_NAME   \
        --versioning-configuration  \
        Status=Enabled
  if [ $? != 0 ]; then
    echo "Bucket versioning configuration failed"
    delete_bucket
    exit
  fi
END

  aws s3api put-bucket-encryption \
        --bucket $BUCKET_NAME \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  if [ $? != 0 ]; then
    echo "Bucket encryption configuration failed"
    delete_bucket
    exit
  fi

  export NAME=$NAME
  export KOPS_STATE_STORE="s3://$BUCKET_NAME"

: <<'END'
  kops create secret \
        --name $NAME \
        sshpublickey admin -i ~/.ssh/id_rsa.pub
  if [ $? != 0 ]; then
    echo "kops create secret failed"
    exit
  fi
END

 #--topology private \
 
  kops create cluster \
  --cloud=aws \
  --master-zones=$ZONE1 \
  --zones=$ZONE1 \
  --node-count=1 \
  --networking kopeio-vxlan \
  --node-size=t2.large \
  --master-size=t2.medium \
  ${NAME}

  if [ $? != 0 ]; then
    echo "kops create cluster failed"
    exit
  fi

  kops update cluster $NAME --yes
  if [ $? != 0 ]; then
    echo "kops update cluster failed"
    exit
  fi


  kops validate cluster
  while [ $? != 0  ]
  do
    sleep 60
    kops validate cluster
  done

  kubectl get pod -n kube-system
  if [ $? != 0 ]; then
    echo "kubectl get pods failed"
    exit
  fi
  
: <<'END'
  kops create instancegroup bastions --role Bastion --subnet utility-$ZONE1 --name ${NAME}
  if [ $? != 0 ]; then
    echo "bastions node creation failed"
    exit
  fi

  kops update cluster ${NAME} --yes
  if [ $? != 0 ]; then
    echo "bastion update to cluster failed"
    exit
  fi

  kops validate cluster
  while [ $? != 0  ]
  do
    sleep 5
    kops validate cluster
  done

  bastion = aws elb --output=table describe-load-balancers|grep DNSName.\*bastion|awk '{print $4}'
  while [ $? != 0  ]
  do
    sleep 5
    bastion = aws elb --output=table describe-load-balancers|grep DNSName.\*bastion|awk '{print $4}'
  done

  echo "Bastion Node: $bastion"
END

: <<'END'
  if [ kubectl apply -f \
        https://raw.githubusercontent.com/kubernetes/kops/master/addons/prometheus-operator/v0.26.0.yaml
       != 0 ]; then
    echo "prometheus setting failed"
    exit
  fi 

  if [ kubectl apply -f \
        https://raw.githubusercontent.com/kubernetes/kops/master/addons/kubernetes-dashboard/v1.10.1.yaml 
        != 0 ]; then
    echo "dashboard setting failed"
    exit
  fi
  if [ kubectl apply -f \
        https://raw.githubusercontent.com/kubernetes/kops/master/addons/logging-elasticsearch/v1.7.0.yaml
      != 0 ]; then
    echo "logging elastic search setting failed"
    exit
  fi
  
  if [ kubectl apply -f install/kubernetes/helm/helm-service-account.yaml 
        != 0 ]; then
    echo "isto service account setup failed"
    exit
  fi

  if [ helm init --service-account tiller != 0 ]; then
    echo "istio helm tiller setup failed"
    exit
  fi

  if [ helm install install/kubernetes/helm/istio --name istio --namespace istio-system
        != 0 ]; then
    echo "istio setup failed"
    exit
  fi
END
}

delete() {
  export KOPS_STATE_STORE="s3://$BUCKET_NAME"
  kops delete cluster $NAME --yes
  if [ $? != 0 ]; then
    echo "kops delete failed"
    exit
  fi
  delete_bucket
}

delete_bucket() {

#  delete_versions
  aws s3 rm s3://$BUCKET_NAME --recursive
  if [ $? != 0 ]; then
    echo "s3 files delete failed"
    exit
  fi

  aws s3api delete-bucket --bucket $BUCKET_NAME --region $REGION
  if [ $? != 0 ]; then
    echo "s3 bucket delete failed"
    exit
  fi
}

delete_versions() {
  bucket=$BUCKET_NAME

  set -e

  echo "Removing all versions from $bucket"

  versions=`aws s3api list-object-versions --bucket $bucket |jq '.Versions'`
  markers=`aws s3api list-object-versions --bucket $bucket |jq '.DeleteMarkers'`

  echo "removing files"
  for version in $(echo "${versions}" | jq -r '.[] | @base64'); do 
      version=$(echo ${version} | base64 --decode)

      key=`echo $version | jq -r .Key`
      versionId=`echo $version | jq -r .VersionId `
      cmd="aws s3api delete-object --bucket $bucket --key $key --version-id $versionId"
      echo $cmd
      $cmd
  done

  echo "removing delete markers"
  for marker in $(echo "${markers}" | jq -r '.[] | @base64'); do 
      marker=$(echo ${marker} | base64 --decode)

      key=`echo $marker | jq -r .Key`
      versionId=`echo $marker | jq -r .VersionId `
      cmd="aws s3api delete-object --bucket $bucket --key $key --version-id $versionId"
      echo $cmd
      $cmd
  done
}

if [ $# != 3 ]; then
  echo "usage: kops.sh <create/delete> <name> <key>"
fi

if [ "$1" = "create" ]; then
  create()
elif [ "$1" = "delete" ]; then
  delete
elif [ "$1" = "delete-bucket" ]; then
  delete_bucket
else 
  echo "usage: kops.sh <create/delete> <name>"
fi

