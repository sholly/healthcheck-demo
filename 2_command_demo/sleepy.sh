#!/bin/sh 

set -x 

sleep 10

echo "healthy" > /tmp/health

while :
do
  sleep 3
  echo `date`
  echo "still sleeping.."
done