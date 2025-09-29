This section provides a convenient way to build the Alloy images per level.
As described in this [post](https://medium.com/p/394ebabea7), we limit the depth to 3 levels (from 0 to 2).

1) Import the Alloy and Loki images

Move to the folder ```commons``` and then type the following commands

```bash
sudo ./import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name grafana/loki --image-version 3.0.0
sudo ./import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name grafana/alloy --image-version v1.10.2
```

2) Build the customized Alloy images

Move to the ```folder part7/alloy``` and then type the following commands

```bash
chmod +x ./build-alloy-images.sh
sudo ./build-alloy-images.sh --local-registry-address <LOCAL_REGISTRY_IP_ADDRESS> --level-number 0
sudo ./build-alloy-images.sh --local-registry-address <LOCAL_REGISTRY_IP_ADDRESS> --level-number 1
sudo ./build-alloy-images.sh --local-registry-address <LOCAL_REGISTRY_IP_ADDRESS> --level-number 2
```

3) Then update the stack ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:<LOCAL_REGISTRY_PORT> LOKI_CONFIG=$(realpath ../part4/4-0/data/configs/loki-config.yaml) docker stack deploy --compose-file docker-compose.yml iot-stack```

To check the installation, please check the [list of the useful commands](../../../docker-swarm-useful-commands.md).

---
# Troubleshootings

If you face any issues, please refer to this [page](../../../docker-swarm-troubleshooting.md).
