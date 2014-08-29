#!/bin/sh 

set -ex

idesc() {
    aws ec2 describe-instances --instance-ids $1
}

istat() {
    idesc $1 | jq --raw-output '.Reservations[0].Instances[0].State.Name'
}

is_istat() {
    istat $1 | grep -q $2
}

iaddr() {
    idesc $1 | jq --raw-output '.Reservations[0].Instances[0].NetworkInterfaces[0].PrivateIpAddresses[0].Association.PublicIp'
}

aws ec2 delete-key-pair --key-name TestNginxKey || true

rm -f key.pem
aws ec2 create-key-pair --key-name TestNginxKey --query 'KeyMaterial' \
    --output text >key.pem && chmod 400 key.pem
ssh-add key.pem
aws ec2 describe-key-pairs

aws ec2 run-instances \
    --image-id ami-7cbc1914 \
    --count 1 \
    --instance-type t1.micro \
    --key-name TestNginxKey \
    --security-groups coreos-testing \
    >instance.json

iid=$(cat instance.json | jq --raw-output '.Instances[0].InstanceId')

while is_istat $iid pending; do sleep 1s; done

if ! is_istat $iid running; then
    echo Oooops...
    aws ec2 terminate-instances --instance-ids $iid
    exit 1
fi

iaddr $iid

sleep 10s

ssh -A -o StrictHostKeyChecking=no -i ./key.pem core@$(iaddr $iid) -- /bin/bash -c " \
  set -ex; \
  docker run -d --name ng -p 8080:80 -p 9090:9000 \
      -e \"AWS_S3_BUCKET=${AWS_S3_BUCKET}\" \
      -e \"AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}\" \
      -e \"AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}\" \
      planitar/test-nginx \
"

ssh -A -o StrictHostKeyChecking=no -i ./key.pem core@$(iaddr $iid) -- /bin/bash -c " \
  set -ex; \
  docker  run -ti --rm --net host \
   -e \"AWS_S3_BUCKET=${AWS_S3_BUCKET}\" \
   -e \"NGINX_PORT=8080\" \
   -e \"APP_PORT=9090\" \
  planitar/test-nginx /src/test.sh small.txt; \
"

ssh -A -o StrictHostKeyChecking=no -i ./key.pem core@$(iaddr $iid) -- /bin/bash -c " \
  set -ex; \
  docker rm -f ng; \
"

aws ec2 terminate-instances --instance-ids $iid
aws ec2 delete-key-pair --key-name TestNginxKey
ssh-add -d key.pem

# aws cloudformation delete-stack --stack-name nginx-test
# url=$(curl -sf https://discovery.etcd.io/new)
# aws cloudformation create-stack \
#     --region us-east-1 \
#     --template-body file://./coreos-beta-pv.template \
#     --stack-name nginx-test \
#     --parameters \
#       ParameterKey=InstanceType,ParameterValue=t1.micro \
#       ParameterKey=ClusterSize,ParameterValue=1 \
#       ParameterKey=DiscoveryURL,ParameterValue=$url \
#       ParameterKey=KeyPair,ParameterValue=TestNginxKey

# aws ec2 delete-key-pair --key-name TestNginxKey
