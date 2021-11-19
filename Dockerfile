# syntax=docker/dockerfile:1
FROM ubuntu:20.04

ARG KUBE_VERSION="1.22.0"

COPY entrypoint.sh /entrypoint.sh

RUN curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
RUN apt-get install apt-transport-https --yes && \
    apt-get update && apt-get install -y curl && \
    chmod +x /entrypoint.sh && \
    curl -LO https://dl.k8s.io/release/v$KUBE_VERSION/bin/linux/amd64/kubectl && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    apt-get install helm --yes

ENTRYPOINT ["/entrypoint.sh"]
CMD ["cluster-info"]
