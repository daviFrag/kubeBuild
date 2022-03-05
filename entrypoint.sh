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

if [ ${DELETE} == "true" ]; then
    helm uninstall ${KUBE_NAMESPACE} --namespace="$KUBE_NAMESPACE"
    if [ $TYPE == "django" ]; then
        helm uninstall "${KUBE_NAMESPACE}-postgresql" --namespace="$KUBE_NAMESPACE"
        helm uninstall "${KUBE_NAMESPACE}-rabbitmq" --namespace="$KUBE_NAMESPACE"
    fi
    if [ $TYPE == "go-graph" ]; then
        helm uninstall "${KUBE_NAMESPACE}-postgresql" --namespace="$KUBE_NAMESPACE"
        helm uninstall "${KUBE_NAMESPACE}-redis" --namespace="$KUBE_NAMESPACE"
    fi
    kubectl delete namespace ${KUBE_NAMESPACE}
    exit 0
fi

if [ -z "${KUBE_NAMESPACE}" -o -z "${DOCKER_PASSWORD}" -o -z "${GITHUB_SHA}" ]; then
    echo "No config found. Please provide KUBE_NAMESPACE, DOCKER_PASSWORD and GITHUB_SHA . Exiting..."
    exit 1
fi


kubectl create namespace ${KUBE_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

if [ $TYPE == "django" ]; then
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm upgrade --install \
        --set fullnameOverride="${KUBE_NAMESPACE}-postgresql" \
        --set auth.username="${POSTGRES_USER}" \
        --set auth.password="${POSTGRES_PASSWORD}" \
        --set auth.database="${POSTGRES_DB}" \
        --set auth.enablePostgresUser=false \
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

if [ $TYPE == "go-graph" ]; then
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm upgrade --install \
        --set fullnameOverride="${KUBE_NAMESPACE}-postgresql" \
        --set auth.username="${POSTGRES_USER}" \
        --set auth.password="${POSTGRES_PASSWORD}" \
        --set auth.database="${POSTGRES_DB}" \
        --set auth.enablePostgresUser=false \
        --set image.tag="${POSTGRES_VERSION}" \
        --namespace="$KUBE_NAMESPACE" \
        --set volumePermissions.enabled=true \
        "${KUBE_NAMESPACE}-postgresql" \
        bitnami/postgresql

    helm upgrade --install \
        --set auth.password="${REDIS_PASSWORD}" \
        --set cluster.slaveCount=1 \
        --set securityContext.enabled=true \
        --set securityContext.fsGroup=2000 \
        --set securityContext.runAsUser=1000 \
        --set volumePermissions.enabled=true \
        --set master.persistence.enabled=true \
        --set slave.persistence.enabled=true \
        --set master.persistence.enabled=true \
        --set master.persistence.path=/data \
        --set master.persistence.size=8Gi \
        --set master.persistence.storageClass=manual \
        --set slave.persistence.enabled=true \
        --set slave.persistence.path=/data \
        --set slave.persistence.size=8Gi \
        --set slave.persistence.storageClass=manual \
        --namespace="${KUBE_NAMESPACE}" \
        "${KUBE_NAMESPACE}-redis" \
        bitnami/redis


    # TODO DA SISTEMARE L'URL O SE NO AGGIUNGERE IL FRONT URL 
    helm upgrade --install \
        --set fullnameOverride="$test-postgresql" \
        --namespace="${KUBE_NAMESPACE}" \
        --set volumePermissions.enabled=true \
        "test-postgresql" \
        bitnami/postgresql

    helm upgrade --install kratos -f oryauth/kratos.yaml \
        --set kratos.serve.public.base_url="https://${URL}/.ory/kratos/public/" \
        --set kratos.session.cookie.domain="${URL}" \
        --set kratos.config.selfservice.default_browser_return_url="https://${URL}" \
        --set kratos.config.selfservice.whitelisted_return_urls[0]="https://${URL}" \
        --set kratos.config.selfservice.whitelisted_return_urls[1]="https://${URL}/login" \
        --set kratos.config.selfservice.flows.login.ui_url="https://${URL}/login" \
        --set kratos.config.selfservice.flows.settings.ui_url="https://${URL}/settings" \
        --set kratos.config.selfservice.flows.recovery.ui_url="https://${URL}/recovery" \
        --set kratos.config.selfservice.flows.verification.ui_url="https://${URL}/verification" \
        --set kratos.config.selfservice.flows.verification.after.default_browser_return_url="https://${URL}/login" \
        --set kratos.config.selfservice.flows.logout.ui_url="https://${URL}/logout" \
        --set kratos.config.selfservice.flows.registration.ui_url="https://${URL}/registration" \
        --set kratos.config.selfservice.flows.error.ui_url="https://${URL}/error" \
        --namespace="${KUBE_NAMESPACE}" \
        ory/kratos
    
    helm upgrade --install keto -f oryauth/keto.yaml ory/keto --namespace="${KUBE_NAMESPACE}"

    helm upgrade --install oathkeeper -f oryauth/oathkeeper.yaml \ 
        --set oathkeeper.config.errors.handlers.redirect.config.to="https://${URL}/login" \
        --set oathkeeper.config.mutators.id_token.issuer_url="https://${URL}" \
        --set ingress.proxy.hosts[0].host="${URL}" \
        --set ingress.api.hosts[0].host="${URL}" \
        ory/oathkeeper \
        --namespace="${KUBE_NAMESPACE}"

    
fi

kubectl create secret \
    docker-registry ${TYPE}-${KUBE_NAMESPACE} \
    --docker-server=${DOCKER_REGISTRY} \
    --docker-username="${DOCKER_USERNAME}" \
    --docker-password="${DOCKER_PASSWORD}" -o yaml --dry-run=client | kubectl replace -n "${KUBE_NAMESPACE}" --force -f -
    

if [ $TYPE == "django" ]; then
    mv $TYPE deploy
elif [ $TYPE == "nextjs" ]; then
    mv $TYPE deploy
elif [ $TYPE == "go-graph" ]; then
    mv $TYPE deploy
fi

helm upgrade ${KUBE_NAMESPACE} ./deploy --install \
    --set image.repository=${IMAGE_LINK} \
    --set image.users=${IMAGE_USERS} \
    --set image.pi=${IMAGE_PI} \
    --set image.gateway=${IMAGE_GATEWAY} \
    --namespace="${KUBE_NAMESPACE}" \
    --set url=${URL} \
    --set environment="${ENVIRONMENT}" \
    --set image.secret=${TYPE}-${KUBE_NAMESPACE} \
    --set-string application.name="${KUBE_NAMESPACE}" \
    --set postgresqlUsername="${POSTGRES_USER}" \
    --set-string postgresqlPassword="${POSTGRES_PASSWORD}" \
    --set postgresqlDatabase="${POSTGRES_DB}" \
    --set rabbitmq.user="${RABBITMQ_USER}" \
    --set-string rabbitmq.psw="${RABBITMQ_PSW}" \
    --set rabbitmq.vhost="${RABBITMQ_VHOST}" \
    --set redis.password="${REDIS_PASSWORD}" \
    --timeout 30m0s
