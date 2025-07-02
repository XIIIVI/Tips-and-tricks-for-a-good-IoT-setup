This section provides a convenient way to build a cluster for VictoriaMetrics (time series) as described in [part #6](https://medium.com/p/aeedbf038511).

> ⚠️ You must configure a dedicated storage for VictoriaMetrics ON ALL YOUR DEVICES by running the following commands
>
```bash
sudo mkdir -p /data/victoriametrics
sudo chown root:root /data/victoriametrics
sudo chmod 744 /data/victoriametrics
```

1) Import the VictoriaMetrics images

```bash
sudo ../../commons/import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name victoriametrics/vminsert --image-version v1.119.0-cluster
sudo ../../commons/import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name victoriametrics/vmstorage --image-version v1.119.0-cluster
sudo ../../commons/import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name victoriametrics/vmselect --image-version v1.119.0-cluster
sudo ../../commons/import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name victoriametrics/vmauth --image-version v1.119.0
```

2) To make Telegraf able to publish into VictoriaMetrics, run the command ```sudo ./update-telegraf-level0.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT>```

3) Then update the stack ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:4443 docker stack deploy --compose-file docker-compose.yml iot-stack```

To list the services on a given node: ```sudo docker node ps <Node's name>```

To remove the stack, type ```sudo docker stack rm iot-stack```

---
Troubleshootings

If the deployment does not work (CURRENT STATE set to Rejected), check this contraint 

⚠️ ON ALL THE CLIENTS, copy $REGISTRY_DIR/certs/registry.crt into /usr/local/share/ca-certificates/registry.crt

```bash

sudo mkdir -p /usr/local/share/ca-certificates/ && vi /usr/local/share/ca-certificates/registry.crt

sudo mkdir -p /etc/docker/certs.d/<IP_ADDRESS_OF_THE_REPO>:4443/ && sudo vi /etc/docker/certs.d/<IP_ADDRESS_OF_THE_REPO>:4443/ca.crt

sudo systemctl restart docker

sudo systemctl status docker

```
