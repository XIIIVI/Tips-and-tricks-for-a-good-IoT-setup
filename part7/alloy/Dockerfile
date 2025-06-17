ARG LOCAL_REGISTRY= <IP_ADDRESS >:4443
ARG IMAGE_VERSION=1.9.1

# Final stage: use the same or another base image
FROM ${LOCAL_REGISTRY}/grafana/alloy:${IMAGE_VERSION}

ENV PARENT_ALLOY_PORT=3100

COPY ./config.alloy /etc/alloy/config.alloy
COPY ./banner /banner
COPY ./entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE ${PARENT_ALLOY_PORT}
# General Alloy API if needed
EXPOSE 12345

CMD ["run", "/etc/alloy/config.alloy", "--server.http.listen-addr=0.0.0.0:12345", "--storage.path=/alloy/data"]