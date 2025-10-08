# Useful commands

---

## Configuration

* To list the imported configurations: ```sudo docker config ls```
* To add a new configuration file to the swarm: ```sudo docker config create <CONFIGURATION_NAME> <PATH_TO_THE_FILE>```
* To display the content of a configuration: ```sudo docker config inspect <CONFIGURATION_NAME>```

---

## Networks

* Tu check which services uses an overlay network: ```sudo docker network inspect <OVERLAY_NETWORK>```

---

## Nodes

* To list the services on a given node: ```sudo docker node ps <Node's name>```

---

## Secrets

* To list the imported secrets: ```sudo docker secret ls```
  
---

## Services

* Display the details of a service: ```sudo docker service inspect <SERVICE_NAME> --pretty```
* List all the services: ```sudo docker service ls```
* Remove a single service: ```sudo docker service rm <Name of the service>```
* Remove all the services: ```sudo docker service rm $(sudo docker service ls -q)```
* Restart a service: ```sudo docker service update --force <SERVICE_NAME>```
* Run a command/shell in the service

On the host, run the following commands

1) Get the container ID: ```CID=$(sudo docker ps --filter name=<SERVICE_NAME> --format '{{.ID}}' | head -n1)```

2) Run the command: ```sudo docker exec -it "$CID" bash```(or ```sudo docker exec -it "$CID" sh```) to open a console or ```sudo docker exec -it "$CID" sh -c '<COMMAND>'``` to execute a command

### Logs

* To display the logs of a service: ```sudo docker service logs <Service's name>```
* To display the logs of a service and follow any appended records: ```sudo docker service logs --follow <Service's name>```
* To display the logs of a service from the end: ```sudo docker service logs --tail <Number of line> <Service's name>```

---

## Stacks

* To list the stacks: ```sudo docker stack list``` 
* To list all the services of a given stack: ```sudo docker stack ps <STACK_NAME>   ``` 
* To update a stack: ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:<LOCAL_REGISTRY_PORT> docker stack deploy --compose-file docker-compose.yml <Name of the stack>```
* To fully remove the stack, type ```sudo docker stack rm iot-stack```

---

## Volumes

* To list all the volumes: ```sudo docker volume ls```

---

## Unused resources

* To remove unused networks: ```docker network prune```
* To remove unused volumes: ```docker volume prune```
* To remove unused images: ```docker image prune -a```
* To remove all unused resources: ```docker system prune -a```
