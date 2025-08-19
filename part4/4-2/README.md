# Deployment

Before deploying this stack, ensure you are using the private repo. You can use one of the following methods

1) update the file .env and then call ```sudo docker stack deploy --compose-file docker-compose.yml iot-stack```,
2) or use this command line ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:<LOCAL_REGISTRY_PORT> docker stack deploy --compose-file docker-compose.yml iot-stack```,

To list the services on a given node: ```sudo docker node ps <Node's name>```

To remove the stack, type ```sudo docker stack rm iot-stack```

---
Troubleshootings

If the deployment does not work (CURRENT STATE set to Rejected), check this contraint 

⚠️ ON ALL THE CLIENTS, copy $REGISTRY_DIR/certs/registry.crt into /usr/local/share/ca-certificates/registry.crt

```bash

sudo mkdir -p /usr/local/share/ca-certificates/ && vi /usr/local/share/ca-certificates/registry.crt

sudo update-ca-certificates
sudo systemctl restart docker
sudo systemctl status docker

```
