# syntax=docker/dockerfile:1
FROM dtzar/helm-kubectl:3.15.4

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh 

ENTRYPOINT ["/entrypoint.sh"]
CMD ["cluster-info"]
