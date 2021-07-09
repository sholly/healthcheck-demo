# A quick demo on Openshift health checks

This is a quick demo on how to do application health checks on Openshift. 

There are three types of health checks: 
1. LivenessProbe
2. ReadinessProbe
3. Startup Probe

We will not cover startup probes in this demo, and focus on liveness and readinesss probes.

A liveness probe determines if the application in the container is still running, whereas a readiness probe determines if the container is ready to accept service requests.  

There are 3 types of health checks: 
1.  HTTP GET checks, which call an endpoint exposed by the app to determine liveness and/or readiness.  
2.  Command-based checks, in which Openshift executes a command within the container to determine if the application is still running.  
3.  TCP server connection checks, not covered in this demo, involve connecting to a TCP port exposed by the container.  

## Code used: 

This demo is self-contained, but the source code for the Java application is here: 
https://github.com/sholly/openshift-java-demo.

The command demo is self contained as well.


## 1 Http GET health checks

Now we'll use the deployment files in 1_httpdemo/deploy-yaml to deploy the HTTP get 
health check.  The code is a simple Spring Boot application that has a single api endpoint, /todos, which reads Todo objects from a Postgresql database.  
 
First, create a new project: 

`oc new-project healthcheck-demo`

Then, run
`oc apply -f 1_httpdemo/deploy-yaml/` 
to deploy the application as well as the needed Postgres database.  We will leave the database uninitialized to illustrate an app that is not ready, and potentially not live. 

Examine the health checks configured in the deployment config: 

```yaml
       livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /actuator/health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 5
          successThreshold: 1
          timeoutSeconds: 2
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /todos
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 2
```
The Spring Boot application has Spring Boot actuator enabled, so we use it to determine liveness.
The readiness probe uses the /todos API endpoint, which is currently returning errors since our database is not
initialized.

Check on the pod health via `oc get pods` : 
```shell
NAME                 READY   STATUS      RESTARTS   AGE
java-demo-1-4ts58    0/1     Running     0          4m18s
```

Since /actuator/env is up, but /todos is failing, we have an app that is live, but not ready.  

If we attempt to call the /todos endpoint, we will get a message from Openshift stating that this app is 
'not currently serving requests at this endpoint'


Now, let's set the liveness probe to /todos.  
Run `oc edit deploymentconfig java-demo`, and change livenessProbe.httpGet.path to /todos.  

Check on the pod health again via `oc get pods`:
```shell
NAME                 READY   STATUS      RESTARTS   AGE
java-demo-2-4k295    0/1     Running     3          79s
```

Note how the application pod is restarting frequently; 

Eventually it will wind up in CrashLoopBackoff status: 
```shell
java-demo-2-4k295    0/1     CrashLoopBackOff   4          2m
```


Now initialize database: 

Get the database pod name, and forward 5532 to 5432 in the database container: 
`oc port-forward tododb-1-$PODNAME 5532:5432`

Change directory to 1_httpdemo. 
Run 

`psql -h localhost -p 5532 -U todo`,

at the prompt, run 

`todo=> \i todo.openshift.sql`

to initialize the database.  

Now observe that we have a live, ready application: 

```shell
NAME                 READY   STATUS      RESTARTS   AGE
java-demo-2-4k295    1/1     Running     6          5m18s
java-demo-2-deploy   0/1     Completed   0          5m21s
```


## 2 Command-based health check
Now we'll examine a command-based health check.  

In the directory 2_command_demo, examine the sleepy.sh script, and the Dockerfile.  It is
It deploys a container with a simple shell script that sleeps for 10 sec, creates /tmp/health, then sleeps forever.

Examine the livenessProbe in 2_command_demo/deployment-live.yaml.  We check for the existing of /tmp/health to determine
liveness: 

```yaml
          livenessProbe:
            exec:
              command:
                - cat 
                - /tmp/health
            initialDelaySeconds: 5
            timeoutSeconds: 1
            periodSeconds: 5
            successThreshold: 1
            failureThreshold: 3
```

In the same project run: 

`oc apply -f deployment_live.yaml`

The livenessProbe will initially check after 5 seconds, then check every 5 seconds.  Three failures are required for 
a pod restart. 

Now, let's rsh into the sleepy pod, remove /tmp/health, and observe what happens.
Run: 

`oc rsh $sleepypod`

`$ rm /tmp/health`

We can  run `oc get pods -w` to watch the pods, or we can run `oc get events -w` to watch the Openshift events in the 
curent namespace. 

The output of `oc get events -w` clearly illustrates what happens: 

```shell
0s          Warning   Unhealthy                     pod/sleepy-74db976b84-7n2nz         Liveness probe failed: cat: can't open '/tmp/health': No such file or directory
0s          Warning   Unhealthy                     pod/sleepy-74db976b84-7n2nz         Liveness probe failed: cat: can't open '/tmp/health': No such file or directory
0s          Normal    Killing                       pod/sleepy-74db976b84-7n2nz         Container sleepy failed liveness probe, will be restarted
0s          Normal    Pulling                       pod/sleepy-74db976b84-7n2nz         Pulling image "docker.io/sholly/sleepy:1.0"
0s          Normal    Pulled                        pod/sleepy-74db976b84-7n2nz         Successfully pulled image "docker.io/sholly/sleepy:1.0" in 880.895278ms
0s          Normal    Created                       pod/sleepy-74db976b84-7n2nz         Created container sleepy
0s          Normal    Started                       pod/sleepy-74db976b84-7n2nz         Started container sleepy
```
After 3 failed health checks, Openshift decides that the pod has failed the livnessProbe, and must be restarted. 
