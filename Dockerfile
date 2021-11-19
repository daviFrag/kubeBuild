# syntax=docker/dockerfile:1
FROM ubuntu:20.04

ARG KUBE_VERSION="1.22.0"

COPY entrypoint.sh /entrypoint.sh

RUN apt-get update && apt-get install -y curl && \
    chmod +x /entrypoint.sh && \
    curl -LO https://dl.k8s.io/release/v$KUBE_VERSION/bin/linux/amd64/kubectl && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

ENTRYPOINT ["/entrypoint.sh"]
CMD ["cluster-info"]
