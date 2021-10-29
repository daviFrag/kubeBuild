FROM alpine:3.10.2
MAINTAINER Davide Frageri <davide.frag@gmail.com>

ARG KUBE_VERSION="1.22.0"

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh && \
    apk add --no-cache --update openssl curl ca-certificates && \
    curl -L https://storage.googleapis.com/kubernetes-release/release/v$KUBE_VERSION/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl && \
    rm -rf /var/cache/apk/*

RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

ENTRYPOINT ["/entrypoint.sh"]
CMD ["cluster-info"]
