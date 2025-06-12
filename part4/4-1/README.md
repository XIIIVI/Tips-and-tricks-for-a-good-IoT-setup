# Deployment

Before deploying this stack, ensure you are using the private repo. You can use one of the following methods

1) update the file .env and then call docker stack ```deploy --compose-file docker-compose.yml iot-stack```,
2) or use this command line ```PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:4443 docker stack deploy --compose-file docker-compose.yml iot-stack```,
3) or this piece of code

```bash
export PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:4443
docker stack deploy --compose-file docker-compose.yml iot-stack
```
