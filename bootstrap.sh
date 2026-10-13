#!/bin/bash
set -e

kubectl create namespace todoapp --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f pv.yml
kubectl apply -f pvc.yml
kubectl apply -f configmap.yml
kubectl apply -f secret.yml
kubectl apply -f deployment.yml

kubectl rollout status deployment/todoapp -n todoapp