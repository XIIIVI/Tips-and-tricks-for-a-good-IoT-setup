This section provides a convenient way to build the Telegraf images per level.
As described in this [post](https://medium.com/p/394ebabea7), we limit the depth to 3 levels (from 0 to 2).










Before deploying this stack, ensure you are using the private repo. You can use one of the following methods

1) update the file .env and then call docker stack ```deploy --compose-file docker-compose.yml iot-stack```,
2) or use this command line ```PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:4443 docker stack deploy --compose-file docker-compose.yml iot-stack```,
3) or this piece of code

```bash
export PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:4443
docker stack deploy --compose-file docker-compose.yml iot-stack
```

To remove the stack, type ```sudo docker stack rm iot-stack```
