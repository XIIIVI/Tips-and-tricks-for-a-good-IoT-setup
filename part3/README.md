As a pre-requisite, don't forget to install the certificate of the registry (docker-registry/certs/registry.crt) on each client as explained at the end of the local registry installation.

⚠️ ON ALL THE CLIENTS, copy $REGISTRY_DIR/certs/registry.crt into /usr/local/share/ca-certificates/registry.crt
Then run 'sudo update-ca-certificates' to trust the self-signed certificate.
Finally, restart the Docker service with 'sudo systemctl restart docker'.
