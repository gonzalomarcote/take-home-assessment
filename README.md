# Gonzo's Take Home Assessment
Gonzalo Marcote `Take Home Assessment` project.
This repository contains a simple Docker-based Python application with Kubernetes deployment and CI/CD setup.


## General questions

### 1. Create an image with python2, python3, R, install a set of requirements and upload it to docker hub
```
FROM python:3.8
LABEL maintainer="Gonzalo Marcote <gonzalomarcote@gmail.com>"
LABEL version="0.1"

# Install boto3
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

CMD ["sleep", "infinity"]
```

You can check [Dockerfile](./Dockerfile) here


### 2. For the previously created image Share build times
Build it with:
`time docker build -t gonzalomarcote/assessment:latest .`

First time build (pulling python:3.8 image) takes 1 min and 16 seconds:
```
real	1m16,432s
user	0m0,187s
sys	0m0,139s
```

You could improve build times by:
* Use multi-stage image to separate build and runtime layers
* Use specific version of `python:3.8-slim` instead of latest or use smaller base images like `python:3.8-alpine`
* Use `.dockerignore` to exclude unnecessary files

Push it (after login to Docker Hub with `docker login`) with:
```
docker push gonzalomarcote/assessment
Using default tag: latest
The push refers to repository [docker.io/gonzalomarcote/assessment]
383dedda164f: Pushed 
bfb701a43cd5: Pushed 
88320258128f: Pushed 
0796a33961ef: Mounted from library/python 
04f6e4cfc28e: Mounted from library/python 
140ec0aa8af0: Mounted from library/python 
1287fbecdfcc: Mounted from library/python 
latest: digest: sha256:40669fc0181b556692aa066e8d413d66c3a90a754f532bf054331126532269b3 size: 1784
```


### 3. Scan the recently created container and evaluate the CVEs that it might contain. Do it with AWS if possible. If not with docker hub

#### 3.a. Create a report of your findings and follow best practices to remediate the CVE
You can scan our recently created image with:
`docker scan gonzalomarcote/assessment:latest`

However, `scan` option seems to be deprecated in docker so another popular option is `trivy`, one open-source vulnerability scanner:
`trivy image gonzalomarcote/assessment:latest`

Trivy provides detailed CVE reports and is widely used in CI/CD pipelines.

Also if you are using AWS ECR, you can scan it with AWS CLI `aws ecr start-image-scan` or manually from the AWS ECR images portal.


#### 3.b. What would you do to avoid deploying malicious packages?
You can for example use always official docker images, to be sure that to verify package sources or in critical cases to validate checksums.
In my case, one example to validate `boto3` package checksum would be something similar to this [Dockerfile.checksum](./Dockerfile.checksum):
```
FROM python:3.8
LABEL maintainer="Gonzalo Marcote <gonzalomarcote@gmail.com>"
LABEL version="0.1"

# Install curl
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install boto3 with checksum verification
WORKDIR /app

# Define the expected SHA256 checksum for a specific boto3 version
# (This is an example checksum; replace with the actual one from a trusted source)
ENV BOTO3_VERSION=1.37.18
ENV BOTO3_CHECKSUM=1545c943f36db41853cdfdb6ff09c4eda9220dd95bd2fae76fc73091603525d1

# Download boto3 wheel and verify its checksum
RUN curl -LO "https://files.pythonhosted.org/packages/12/94/dccc4dd874cf455c8ea6dfb4c43a224632c03c3f503438aa99021759a097/boto3-${BOTO3_VERSION}-py3-none-any.whl" \
    && echo "${BOTO3_CHECKSUM}  boto3-${BOTO3_VERSION}-py3-none-any.whl" | sha256sum -c - \
    && pip install "boto3-${BOTO3_VERSION}-py3-none-any.whl" \
    && rm "boto3-${BOTO3_VERSION}-py3-none-any.whl"

CMD ["sleep", "infinity"]
```

Build it with `docker build -f Dockerfile.checksum -t gonzalomarcote/assessment:latest .`


### 4. Use the created image to create a kubernetes deployment with a command that will keep the pod running && 5. Expose the deployed resource
You can create a K8s [assessment.yaml](./deploy/assessment.yaml) deployment with a service to expose our image with:
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: assessment-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: assessment
  template:
    metadata:
      labels:
        app: assessment
    spec:
      containers:
      - name: assessment
        image: gonzalomarcote/assessment:latest
        command: ["sleep", "infinity"]
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: assessment-service
spec:
  selector:
    app: assessment
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: LoadBalancer
```

Apply it with `kubectl apply -f deploy/assessment.yaml`


### 6. Every step mentioned above have to be in a code repository with automated CI/CD
I have created one basic GitHub actions deployment [ci-cd.yaml](./.github/workflows/ci-cd.yaml) yaml file.  
Please Note that as I currently don't have one personal K8s cluster (I had it in the past), the deployment step is not functional (it is commented).  


### 7. How would you monitor the above deployment? Explain or implement the tools that you would use
I always try to use Prometheus for metrics collection and Grafana for metics visualization.
For this, you need to have one Prometheus installed in your K8s cluster gathering metrics.  
You can install it for example with:
```
kubectl create namespace monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install prometheus prometheus-community/prometheus --namespace monitoring --create-namespace -f monitoring/prometheus-values.yaml
```

And add to the service something like:
```
kind: Service
metadata:
  annotations:
    prometheus.io/port: "8888"
    prometheus.io/scrape: "true"
  name: assessment-service
spec:
  selector:
    app: assessment
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: LoadBalancer
```

And implement a healthcheck for the deployment pods. For example:
```
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

After configuring Grafana with Prometheus as `datasource` you can set up alerts for CPU/Memory usage thresholds, pod restarts, etc.


## Project
Using kubernetes you need to provide all your employees with a way of launching multiple development environments (different base images, requirements, credentials, others). The following are the basic needs for it.

### 1. UI, CI/CD, workflow or other tool that will allow people to select options for:
To make interactive for the developers to use different options there could be many different solutions like Jenkins, GitHub Actions, GitLab CI-CD or even with ArgoCD. Since we have been using GitHub Actions in this assesment I will try to continue using it and do one small example for the different options with one `workflow_dispatch` to let the devs in the company choose different options

#### 1.a. Base image
With the following block we can let the users select a different docker python image version:
```
  workflow_dispatch:
    inputs:
      image:
        type: choice
        description: Python version to deploy
        options:
        - 3.8
        - 3.9
```

We pass `PYTHON_VERSION` var in the pipe to the build with:
```
    - name: Build and push Docker image
      run: |
        if [ "${{ github.event_name }}" = "push" ]; then
          PYTHON_VERSION="3.8"  # Default for push events from main
        else
          PYTHON_VERSION=${{ github.event.inputs.image }}
        fi
        docker build -t ${{ secrets.DOCKER_USERNAME }}/assessment:latest --build-arg PYTHON_VERSION="$PYTHON_VERSION" .
        docker push ${{ secrets.DOCKER_USERNAME }}/assessment:latest
```

and later we overrride in the [Dockerfile](./Dockerfile) the version by adding at the beginning:
```
ARG PYTHON_VERSION=3.8
FROM python:${PYTHON_VERSION}
```

#### 1.b. Packages
For the pasckages basically the same. We override the [requirements.txt](./requirements.txt) file to install different Python packages depending on the selection in the workflow_dispatch:
```
  workflow_dispatch:
    inputs:
      packages:
        type: choice
        description: Python packages to deploy
        options:
        - boto3
        - json
```

Later into the pipeline we do the trick of overriding the requirements.txt like this:
```
    - name: Set up requirements.txt based on package selection
      run: |
        # Default to boto3 for push events or if boto3 is selected
        PACKAGE="boto3==1.37.18"
        if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
          if [ "${{ github.event.inputs.packages }}" = "json" ]; then
            PACKAGE="python-json-logger==2.0.7"  # Override for json selection
          fi
        fi
        echo "$PACKAGE" > requirements.txt
        echo "Generated requirements.txt with: $PACKAGE"
```

#### 1.c. Mem/CPU/GPU requests
This is more complicated and involve move everything to Helm templates, because it is easier for managing dynamic Kubernetes deployments.  
For example if we add the following workflow_dispatch to the pipeline, based on different specs for the services:  
```
  workflow_dispatch:
    inputs:
      specs:
        type: choice
        description: Mem/CPU/GPU requests
        options:
        - small
        - medium
        - big
```

Later we can create one [specs.yaml](./deploy/charts/values/specs.yaml) file to add different resources:
```
image:
  repository: gonzalomarcote/assessment
  tag: latest

replicas: 1

specs: small  # Default value

resources:
  small:
    requests:
      memory: "128Mi"
      cpu: "50m"
    limits:
      memory: "256Mi"
      cpu: "100m"
  medium:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "200m"
  big:
    requests:
      memory: "512Mi"
      cpu: "200m"
    limits:
      memory: "1Gi"
      cpu: "500m"

service:
  type: LoadBalancer
  port: 80
  targetPort: 8080
```

This will let us make different scenarios to deploy depending of the resources specs needed. We need to modify our previous deployment to use a Helm template [assessment.yaml](./deploy/charts/templates/assessment.yaml) and deploy it with `Helm` instead of `kubectl`:
```
helm upgrade --install assessment ./charts --values charts/values/specs.yaml --set specs=$SPECS
```


### 2. Monitor each environment and make sure that

#### 2.a. Resources request is accurate (requested vs used)
To monitor that requests are accurate (requested vs used) I think the best solution is to monitor it with Grafana. If you are already sending Prometheus metrics from the AWS EKS custer to your Grafana you can monitor your pods CPU and MEM usage with the following metrics:
```
1000 * max(rate(container_cpu_usage_seconds_total{pod=~"assessment-deployment.*",cluster=~"$environment",namespace="default"}[5m])) by (pod)
((sum by (pod) (container_memory_working_set_bytes{pod=~"assessment-deployment..*",cluster=~"$environment",namespace="default"} / 1024) / 1024) / 2)
```

This is what I use in my current company to monitor (dev and prod environments) our different pods.  
Later you can compare it with the CPU and MEM requests:  
```
kube_pod_container_resource_requests{namespace="default", pod=~"assessment-deployment.*",cluster=~"$environment",resource="cpu"}
kube_pod_container_resource_requests{namespace="default", pod=~"assessment-deployment.*",cluster=~"$environment",resource="memory"}
```
And create some Grafana alerts for discrepances and to check if there is a lot of difference.

#### 2.b. Notify when resources are idle or underutilized
As I mentioned above if memory and cpu used is far bellow the requested one that we have specified in the deployment resources we can create some alerts in grafana for example for:
* CPU usage < 10% of requested CPU for 24 hours
* Memory usage < 10% of requested memory for 24 hours

And send alerts (by Slack or email) to the DevOps team to review and adjust it.

#### 2.c. Downscale when needed (you can assume any rule defined by you to allow this to happen)
This I think is pretty complex but affordable. Since I don't have a lot of time for this assessment (I have a full-time job and a kid) I will do an overall explanation with what I would do:
* Create one Cronjob that runs periodically to check if the resources are underutilized or not (for example every hour).
* This Cronjob needs to be deployed with one `ServiceAccount, Role and RoleBinding` to be able to execute `kubectl` commands like `get` and `scale` (and probably someone more) to scale up or down deployment `replicas` according to.
* The Cronjob needs to run some previously cooked pod image that is able to have access to our Prometheus and do queries for the usage VS used resources and compare them to decide if it is underutilized or not (I probably would do this with one python script).

This is what I can imagine now that could be a good solution that could work. But as I commented this seems to be a quite complex task.  
In fact I did something similar to my current company but to scale up and down on specific hours, so I would need to add to the equation one script that check and compare the usage VS used resources.  

#### 2.d. Save data to track people requests/usage and evaluate performance
Honestly I never did something like this. Since the data is already in our prometheus, we could try to build one Grafana Dashboard with a panel that shows the `requested` CPU and MEM for the last 30 days, and in the same dashboard another panel that shows the `used` CPU and MEM for the same period to compare them. But I honestly don't know how to add the Developer name or team that did it. Perhaps using Jenkins or GitHub Actions you can save that Devs or Team name and when a deploy is done and they did a change into the `requested` specs, save it to one postgres database along with the Prometheus time-series data for the metrics we’re collecting (`container_cpu_usage_seconds_total` and `container_memory_working_set_bytes`).


### 3. The cluster needs to automatically handle up/down scaling and have multiple instance groups/taints/tags/others to be chosen from in order to segregate resources usage between teams/resources/projects/others
To handle this I think the best design in one AWS EKS cluster would be to add the following elements:
* Autoscaling - Add `Kubernetes Cluster Autoscaler` to scale up and down nodes on demand. When pods replicas are going up or down (or if you have HPA configured) this will make the AWS EKS cluster to cale the nodes based on resources utilization and pod scheduling needs.
* Node Groups - It would be interesting to deploy AWS EKS cluster with different `Nodegroups`. This Node Gropus can be deployed across multiple AZs. In this way to have multiple Node groups will allow us to separate tehm for different purposes. For example for different teams or projects or workloads (CPU intense workloads, Memory intense workloads... and each one with different instance types). Another nice feature of Node Gropus is that you can update cluster configurations (minSize, maxSize, desiredCapacity, instanceType) without recreating the whole cluster.
* Taints/Tags/Others - With `Taints` you can be sure that only specific pods goes into specific nodes. For example nodes with `team=frontend:NoSchedule` taint makes that only pods with a toleration `team=frontend` can be scheduled in that node. `Tags` can help to tag AWS infra resources (EC2, ELB, volumes, etc) and that will help to identify and track billing costs for one specific Team or Project. Other useful resources to design one cluster that could segregate resources could be `affinity/anti-affinity` rules taht like "preferences" for where pods should run.

### 4. SFTP, SSH or similar access to the deployed environment is needed so DNS handling automation is required


### 5. Some processes that are going to run inside these environments require between 100-250GB of data in memory

#### 5.a. Could you talk about a time when you needed to bring the data to the code, and how you architected this system?

#### 5.b. If you don’t have an example, could you talk through how you would go about architecting this?

#### 5.c. How would you monitor memory usage/errors?
