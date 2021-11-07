#!/bin/sh

# BRANCH_NAME=${GITHUB_REF##*/}
# KUBE_NAMESPACE=$(echo $BRANCH_NAME | tr '[:upper:]' '[:lower:]')

# KUBE_NAMESPACE= "$( echo $META_DATA | jq -r '.org.opencontainers.image.title' )-$( echo $META_DATA | jq -r '.org.opencontainers.image.version' )"

set -e

if [ ! -d "$HOME/.kube" ]; then
    mkdir -p $HOME/.kube
fi

if [ ! -f "$HOME/.kube/config" ]; then
    if [ ! -z "${KUBE_CONFIG}" ]; then

        echo "$KUBE_CONFIG" | base64 -d > $HOME/.kube/config

        if [ ! -z "${KUBE_CONTEXT}" ]; then
            kubectl config use-context $KUBE_CONTEXT
        fi

    elif [ ! -z "${KUBE_HOST}" ]; then

        echo "$KUBE_CERTIFICATE" | base64 -d > $HOME/.kube/certificate
        kubectl config set-cluster default --server=https://$KUBE_HOST --certificate-authority=$HOME/.kube/certificate > /dev/null

        if [ ! -z "${KUBE_PASSWORD}" ]; then
            kubectl config set-credentials cluster-admin --username=$KUBE_USERNAME --password=$KUBE_PASSWORD > /dev/null
        elif [ ! -z "${KUBE_TOKEN}" ]; then
            kubectl config set-credentials cluster-admin --token="${KUBE_TOKEN}" > /dev/null
        else
            echo "No credentials found. Please provide KUBE_TOKEN, or KUBE_USERNAME and KUBE_PASSWORD. Exiting..."
            exit 1
        fi

        kubectl config set-context default --cluster=default --namespace=default --user=cluster-admin > /dev/null
        kubectl config use-context default > /dev/null

    else
        echo "No authorization data found. Please provide KUBE_CONFIG or KUBE_HOST variables. Exiting..."
        exit 1
    fi
fi

echo "/usr/local/bin/kubectl" >> $GITHUB_PATH

if [ ${DELETE} == "true" ]; then
    helm uninstall ${KUBE_NAMESPACE} --namespace="$KUBE_NAMESPACE"
    if [ $TYPE == "django" ]; then
        helm uninstall "${KUBE_NAMESPACE}-postgresql" --namespace="$KUBE_NAMESPACE"
        helm uninstall "${KUBE_NAMESPACE}-rabbitmq" --namespace="$KUBE_NAMESPACE"
    fi
    kubectl delete namespace ${KUBE_NAMESPACE}
    exit 0
fi

if [ -z "${KUBE_NAMESPACE}" -o -z "${IMAGE_LINK}" -o -z "${GITHUB_TOKEN}" -o -z "${GITHUB_SHA}" ]; then
    echo "No config found. Please provide KUBE_NAMESPACE, IMAGE_NAME, GITHUB_TOKEN, GITHUB_EMAIL, GITHUB_SHA and GITHUB_USERNAME. Exiting..."
    exit 1
fi


kubectl create namespace ${KUBE_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
kubectl get secret cert-stage-wildcard -n default --export -o yaml | \
kubectl apply -n ${KUBE_NAMESPACE} -f -

if [ $TYPE == "django" ]; then
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm upgrade --install \
        --set fullnameOverride="${KUBE_NAMESPACE}-postgresql" \
        --set postgresqlUsername="${POSTGRES_USER}" \
        --set-string postgresqlPassword="${POSTGRES_PASSWORD}" \
        --set postgresqlDatabase="${POSTGRES_DB}" \
        --set image.tag="${POSTGRES_VERSION}" \
        --namespace="$KUBE_NAMESPACE" \
        --set volumePermissions.enabled=true \
        "${KUBE_NAMESPACE}-postgresql" \
        bitnami/postgresql

    export check_rabbit=$(helm list --namespace=${KUBE_NAMESPACE} | grep -c rabbitmq)

    if [ $check_rabbit == 0 ]; then
        helm upgrade --install \
        --set auth.username="${RABBITMQ_USER}" \
        --set-string auth.password="${RABBITMQ_PSW}" \
        --set extraConfiguration="default_vhost=${RABBITMQ_VHOST}" \
         --set volumePermissions.enabled=true \
        --namespace="$KUBE_NAMESPACE" \
        "${KUBE_NAMESPACE}-rabbitmq" \
        bitnami/rabbitmq
    fi
fi

kubectl create secret \
    docker-registry ${TYPE}-${KUBE_NAMESPACE} \
    --docker-server=ghcr.io \
    --docker-username="${DOCKER_USERNAME}" \
    --docker-password="${GITHUB_TOKEN}" -o yaml --dry-run=client | kubectl replace -n "${KUBE_NAMESPACE}" --force -f -
    
helm upgrade ${KUBE_NAMESPACE} ./deploy --install \
    --set image.repository=${IMAGE_LINK} \
    --namespace="${KUBE_NAMESPACE}" \
    --set url=${URL} \
    --set image.secret=${TYPE}-${KUBE_NAMESPACE} \
    --set application.name="${KUBE_NAMESPACE}" \
    --set postgresqlUsername="${POSTGRES_USER}" \
    --set-string postgresqlPassword="${POSTGRES_PASSWORD}" \
    --set postgresqlDatabase="${POSTGRES_DB}" \
    --set rabbitmq.user=""${RABBITMQ_USER}"" \
    --set-string rabbitmq.psw=""${RABBITMQ_PSW}"" \
    --set rabbitmq.vhost=""${RABBITMQ_VHOST}"" \
    --timeout 30m0s
