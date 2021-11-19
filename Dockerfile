# syntax=docker/dockerfile:1
FROM dtzar/helm-kubectl:3.7.1

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh 

ENTRYPOINT ["/entrypoint.sh"]
CMD ["cluster-info"]
