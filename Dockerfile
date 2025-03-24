ARG PYTHON_VERSION=3.8
FROM python:${PYTHON_VERSION}
LABEL maintainer="Gonzalo Marcote <gonzalomarcote@gmail.com>"
LABEL version="0.1"

# Install boto3
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

CMD ["sleep", "infinity"]
