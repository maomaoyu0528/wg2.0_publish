#!/bin/bash
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

kubectl apply -f $SCRIPTPATH/system.yml
sleep 5
kubectl apply -f $SCRIPTPATH/web.yml
sleep 5
kubectl apply -f $SCRIPTPATH/ws.yml
sleep 5
kubectl apply -f $SCRIPTPATH/threads.yml
sleep 5
kubectl apply -f $SCRIPTPATH/crash.yml
sleep 5
kubectl apply -f $SCRIPTPATH/front-cm.yml -f $SCRIPTPATH/front.yml
kubectl apply -f $SCRIPTPATH/servicemonitor.yml