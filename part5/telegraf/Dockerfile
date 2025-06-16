# Define build arg for the base image
ARG LOCAL_REGISTRY
ARG IMAGE_VERSION

# Final stage: use the same or another base image
FROM --platform=$TARGETPLATFORM ${LOCAL_REGISTRY}/telegraf:${IMAGE_VERSION}

ENV MODULE_VERSION=#-MODULE_VERSION-#
ENV DEBUG_ON=false
ENV DEBUG_QUIET=false
ENV DEBUG_LOG_ROTATION_INTERVAL_IN_HOUR=0
ENV DEBUG_LOG_ROTATION_MAX_SIZE_IN_MIB=10
ENV DEBUG_LOG_ROTATION_MAX_ARCHIVES=5
# To limit memory consumption for Telegraf
# 300MB is the default value
ENV GOMEMLIMIT=314572800
ENV GOGC=50
ENV GOMAXPROCS=4

COPY ./telegraf.conf /etc/telegraf/telegraf.conf
COPY ./banner /banner
COPY ./entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh && \
    apk update && apk add --no-cache bash jq python3

ENTRYPOINT ["/entrypoint.sh"]

USER root

CMD ["telegraf"]
