##1 Http health check demo

`oc new-project healthcheck-demo`

`oc apply -f 1_httpdemo/deploy-yaml/`

Liveness is set to use /actuator/health

Readiness is set to use /todos, which calls uninitialized database. 


Now set liveness probe to /todos, the pod will start restarting..  

Now initialize database: 

`oc port-forward tododb-1-yxz 5532:5432`

`psql -h localhost -p 5532 -U todo`


##2 Command-based health check

`oc apply -f 2*/deployment_live.yaml`

It deploys a shell script container that sleeps for 10 sec, creates /tmp/health, then sleeps forever.

The livenessProbe will initially check after 5 seconds, then check every 5 seconds.  3 failures required for restart. 

It will complain once, then things will be fine. 

`oc rsh $sleepypod`

`rm /tmp/health`

Now the container will restart after 15 seconds. 
