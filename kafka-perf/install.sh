#!/bin/bash

echo "Running script to create Kafka on Kubernetes cluster"

# Set correct values for your subscription
if [ -z "$CLUSTER_NAME" ]; then
      CLUSTER_NAME="kafka-helm-px"
fi
if [ -z "$RG_NAME" ]; then
      RG_NAME="kafka-helm-rg"
fi
if [ -z "$LOCATION" ]; then
      LOCATION="westus2"
fi
if [ -z "$VM_SIZE" ]; then
      VM_SIZE="Standard_DS5_v2"
fi
if [ -z "$NODE_COUNT" ]; then
      NODE_COUNT=3
fi

echo "Creating AKS Cluster"

az group create -n $RG_NAME -l $LOCATION
az aks create -n $CLUSTER_NAME -g $RG_NAME -l $LOCATION --node-count $NODE_COUNT --node-vm-size $VM_SIZE --generate-ssh-keys 
az aks get-credentials -n $CLUSTER_NAME -g $RG_NAME --overwrite-existing

echo -e "adding RBAC ServiceAccount and ClusterRoleBinding for tiller\n\n"
export timeout=120  #Number of loops before timeout on check on tiller
export wait=5 #Number of seconds between to checks on tiller

kubectl create serviceaccount --namespace kube-system tillersa
if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of tillersa failed"
    # exit 1
fi

kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tillersa
if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of the tiller-cluster-rule failed"
    # exit 1
fi

kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:kubernetes-dashboard
if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of dashboard-admin failed"
    # exit 1
fi

echo "Upgrading tiller (helm server) to match client version."

helm init --upgrade --service-account tillersa
if [ $? -ne 0 ]; then
    echo "[ERROR] The helm init command failed"
    # exit 1
fi

count=0
until kubectl get pods --all-namespaces | grep -E "kube-system(\s){3}tiller.*1\/1\s*Running+"
do
        sleep ${wait}
done

echo "tiller upgrade complete."

echo "installing kafka helm chart"

helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator

helm install --name kafka incubator/kafka -f values.yaml

kubectl rollout status statefulset/kafka

kubectl create -f kafkaclient.yaml

echo "Completed installing Kafka Helm chart and client pod."