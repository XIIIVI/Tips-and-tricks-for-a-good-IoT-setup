# Deployment

Before deploying this stack, ensure you are using the private repo. You can use one of the following methods

1) update the file .env and then call ```sudo docker stack deploy --compose-file docker-compose.yml iot-stack```,
2) or use this command line ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:<LOCAL_REGISTRY_PORT> docker stack deploy --compose-file docker-compose.yml iot-stack```,

To check the installation, please check the [list of the useful commands](../../docker-swarm-useful-commands.md).

---
# Troubleshootings

If you face any issues, please refer to this [page](../../docker-swarm-troubleshooting.md).
