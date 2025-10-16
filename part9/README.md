This section handles some cybersecurity concerns as detailed in this [post](https://medium.com/p/74949dd03941).

Update/deploy the stack ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:<LOCAL_REGISTRY_PORT> docker stack deploy --compose-file docker-compose.yml iot-stack```

To check the installation, please check the [list of the useful commands](../../../docker-swarm-useful-commands.md).

---

# Secured dashboards

The folder ```grizzly``` contains an updated version of the Grafana's dashboards provided in part #8.

These version introduces the usage of the secured version of the Loki datasource.

To install them, please, follow the process detailed in [part #8](../part8/README.md)

---

# Dev version vs production version

The file docker-compose.yml is the development version of the Swarm's configuration.

The file docker-compose-secured.yml applies all the principles described in the post.

To test if your swarm is secured or not, run the script `sudo ./test-secured-swarm.sh --docker-compose <YOUR_DOCKER_COMPOSE_FILE>`

---

# Troubleshootings

If you face any issues, please refer to this [page](../../../docker-swarm-troubleshooting.md).
