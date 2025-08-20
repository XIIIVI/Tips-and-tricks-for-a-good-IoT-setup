# Useful commands

## Nodes
* To list the services on a given node: ```sudo docker node ps <Node's name>```

## Services

* Remove all the services: ```docker service rm $(docker service ls -q)```

### Logs

* To display the logs of a service: ```sudo docker service logs <Service's name>```
* To display the logs of a service and follow any appended records: ```sudo docker service logs --follow <Service's name>```
* To display the logs of a service from the end: ```sudo docker service logs --tail <Number of line> <Service's name>```

## Stacks

* To update a stack: ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:<LOCAL_REGISTRY_PORT> docker stack deploy --compose-file docker-compose.yml <Name of the stack>```
* To fully remove the stack, type ```sudo docker stack rm iot-stack```

## Unused resources

* To remove unused networks: ```docker network prune```
* To remove unused volumes: ```docker volume prune```
* To remove unused images: ```docker image prune -a```
* To remove all unused resources: ```docker system prune -a```
