#!/bin/sh

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

if [ -z "${KUBE_NAMESPACE}" -o -z "${IMAGE_NAME}" -o -z "${GITHUB_TOKEN}" -o -z "${GITHUB_SHA}" ]; then
    echo "No config found. Please provide KUBE_NAMESPACE, IMAGE_NAME, GITHUB_TOKEN, GITHUB_EMAIL, GITHUB_SHA and GITHUB_USERNAME. Exiting..."
    echo "${KUBE_NAMESPACE} ${IMAGE_NAME} ${GITHUB_USERNAME} ${GITHUB_TOKEN} ${GITHUB_SHA} ${GITHUB_REPOSITORY}"
    exit 1
fi


kubectl create namespace ${KUBE_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret docker-registry ${IMAGE_NAME}-${KUBE_NAMESPACE} --docker-server=ghcr.io --docker-username="${DOCKER_USERNAME}" --docker-password="${GITHUB_TOKEN}" -o yaml --dry-run=client | kubectl replace -n "${KUBE_NAMESPACE}" --force -f -
helm upgrade production ./deploy --install --set image.repository=ghcr.io/startup-zgproject/${IMAGE_NAME}:${GITHUB_SHA} --namespace="${KUBE_NAMESPACE}" --set image.secret=${IMAGE_NAME}-${KUBE_NAMESPACE} --timeout 30m0s
