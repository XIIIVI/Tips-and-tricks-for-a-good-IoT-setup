# Define build arg for the base image
ARG LOCAL_REGISTRY=#-IP_ADDRESS-#:#-PORT-#
ARG IMAGE_VERSION=#-IMAGE_VERSION-#

# Final stage: use the same or another base image
FROM ${LOCAL_REGISTRY}/alloy:${IMAGE_VERSION}

ENV MAIN_ALLOY_PORT=3131

COPY ./config.alloy /etc/alloy/config.alloy
COPY ./banner /banner
COPY ./entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE ${MAIN_ALLOY_PORT}
# General Alloy API if needed
EXPOSE 12345

CMD ["run", "/etc/alloy/config.alloy", "--server.http.listen-addr=0.0.0.0:12345", "--storage.path=/alloy/data"]