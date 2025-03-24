# Gonzo's Take Home Assessment
Gonzalo Marcote `Take Home Assessment` project.
This repository contains a simple Docker-based Python application with Kubernetes deployment and CI/CD setup.


## General questions
1. Create an image with python2, python3, R, install a set of requirements and upload it to docker hub
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

2. For the previously created image Share build times
Build it with:
`time docker build -t gonzalomarcote/assessment:latest .`

Firts time (pulling python:3.8 image) it takes 1 min and 16 seconds:
```
real	1m16,432s
user	0m0,187s
sys	0m0,139s
```

You could improve build times by:
* Use multi-stage image to separate build and runtime layers
* Use specific version of python:3.8-slim instead of latest or use smaller base images like python:3.8-alpine
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

3. Scan the recently created container and evaluate the CVEs that it might contain. Do it with AWS if possible. If not with docker hub
* Create a report of your findings and follow best practices to remediate the CVE
You can scan our recently created image with:
`docker scan gonzalomarcote/assessment:latest`

Also if you are using AWS ECR, you can scan it with AWS CLI `aws ecr start-image-scan` or manually from th3 AWS ECR images portal.

* What would you do to avoid deploying malicious packages?
You van for example use always official docker images, be sure that to verufy package sources or in critical cases validate checksums.
In my case, one example to validate `boto3` could be something similar to this:
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

4. Use the created image to create a kubernetes deployment with a command that will keep the pod running && 5. Expose the deployed resource
You can create a K8s deploymet with a service to expose our image with:
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

Apply it with `kubectl apply -f deployment.yaml`

6. Every step mentioned above have to be in a code repository with automated CI/CD
I have created one basic GitHub actions deployment yaml file.  
Please Note that as I currently don't have one personal Ku8s cluster (I had it in the past), the deployment stepd is not functional.  
See the [assessment.yaml](./deploy/assessment.yaml) for details.

7. How would you monitor the above deployment? Explain or implement the tools that you would use
I always try to use Prometheus for metrics collection and Grafana for metics visualization.
For this you need to have one prmetheus installed in your K8s cluster gathering metrics.  
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

And implement a healthcheck for deployment. For example:
```
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

After coniguring Grafana with Prometheus `datasource` you can Set up alerts for CPU/Memory usage thresholds, pod restarts, etc
