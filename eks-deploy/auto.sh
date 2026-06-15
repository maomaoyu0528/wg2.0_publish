#!/bin/bash

clustername="${1?Please provide the cluster name}"
region="${2?Please provide the region}"
profile="${3:-default}"

for file in $(find . -type f -name "*.tpl" -print)
do
    new_file="${file%.tpl}"

    content=$(cat "$file" | sed "s/{{clustername}}/$clustername/g" | sed "s/{{region}}/$region/g" | sed "s/{{profile}}/$profile/g")

    echo "$content" > "$new_file"   
done

echo "开始用eksctl创建eks集群..."

AWS_PROFILE=$profile eksctl create cluster -f eks-cluster.yml

echo "集群创建完成"

check_nodes_ready() {
  nodes_status=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}')

  if echo "${nodes_status}" | grep -q "False"; then
    return 1
  else
    return 0
  fi
}

until check_nodes_ready; do
  echo "等待所有节点变为Ready状态..."
  sleep 5
done

echo "开始部署metrics-server..."
kubectl apply -f components/metrics-server.yaml


while true; do
  deployment_status=$(kubectl get deployments -n kube-system metrics-server | tail -n 1 | awk '{print $4}')
  apiservice_status=$(kubectl get apiservices | grep "metrics.k8s.io" | awk '{print $3}')
  if [ "$deployment_status" == "1" ] && [ "$apiservice_status" == "True" ]; then
    echo "Metrics-server deployment is running"
    break
  else
    echo "Waiting for metrics-server deployment to start"
    sleep 5
  fi
done

echo "开始部署prometheus-stack..."
kubectl create namespace prometheus
helm install monitor components/kube-prometheus-stack-45.10.1.tgz -f components/prom-stack-configs.yml -n prometheus

#sleep 3
#echo "开始部署fluentbit..."
#kubectl apply -f components/fluentbit.yml

sleep 3
echo "开始部署efs-csi-driver..."

AWS_PROFILE=$profile aws iam create-policy --policy-name AmazonEKS_EFS_CSI_Driver_Policy --policy-document file://components/efs-iam-policy.json

accountid=$(AWS_PROFILE=$profile aws sts get-caller-identity --query 'Account' --output text)

eksctl create iamserviceaccount \
    --profile $profile \
    --cluster $clustername \
    --namespace kube-system \
    --name efs-csi-controller-sa \
    --attach-policy-arn arn:aws:iam::$accountid:policy/AmazonEKS_EFS_CSI_Driver_Policy \
    --approve \
    --region $region

helm upgrade -i aws-efs-csi-driver components/aws-efs-csi-driver-2.4.1.tgz \
    --namespace kube-system \
    --set image.repository=602401143452.dkr.ecr.ap-southeast-1.amazonaws.com/eks/aws-efs-csi-driver \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name=efs-csi-controller-sa

sleep 3
echo "开始创建efs文件系统..."
# pip3 install boto3
sudo apt install python3-boto3
python3 components/create_efs.py
kubectl apply -f components/storageclass.yml
echo "开始部署auto-scaler..."
kubectl apply -f components/cluster-autoscaler-autodiscover.yaml

echo "开始打通vpc网络..."
python3 components/vpc_network.py

sleep 3
echo "开始部署业务应用..."
bash apps/deploy.sh

external_ip=$(kubectl get svc front-image-svc -o jsonpath='{.status.loadBalancer.ingress[*].hostname}')

nat_ip=$(AWS_PROFILE=$profile aws --region $region ec2 describe-nat-gateways --filter "Name=tag:alpha.eksctl.io/cluster-name,Values=$clustername" --query 'NatGateways[*].NatGatewayAddresses[*].PublicIp' --output text)

echo "front服务访问地址: " 
echo "$external_ip"

while [ -z "$nat_ip" ]; do
  echo "等待NAT网关成为可用状态..."
  sleep 5
  nat_ip=$(AWS_PROFILE=$profile aws --region $region ec2 describe-nat-gateways --filter "Name=tag:alpha.eksctl.io/cluster-name,Values=$clustername" --query 'NatGateways[*].NatGatewayAddresses[*].PublicIp' --output text)
done

echo "NAT网关的IP地址:: $nat_ip"