This section provides a convenient way to build a customized image of Grafana as described in this [post](https://medium.com/p/157166dce55d).


1) Then update the stack ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:<LOCAL_REGISTRY_PORT> docker stack deploy --compose-file docker-compose.yml iot-stack```

To check the installation, please check the [list of the useful commands](../../../docker-swarm-useful-commands.md).

---
# Troubleshootings

If you face any issues, please refer to this [page](../../../docker-swarm-troubleshooting.md).
