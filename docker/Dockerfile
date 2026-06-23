ARG BASE_IMAGE
FROM ${BASE_IMAGE}

COPY requirements-extras.txt /tmp/requirements-extras.txt
RUN pip install --no-cache-dir -r /tmp/requirements-extras.txt && \
    rm /tmp/requirements-extras.txt
