# check=skip=InvalidDefaultArgInFrom
# BASE_IMAGE deliberately has no default: scripts/build-and-push.sh always
# passes it, and a build without it should fail rather than pick a stale tag.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

COPY requirements-extras.txt /tmp/requirements-extras.txt
RUN pip install --no-cache-dir -r /tmp/requirements-extras.txt && \
    rm /tmp/requirements-extras.txt
