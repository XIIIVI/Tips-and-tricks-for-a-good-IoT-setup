This section provides a convenient way to build a cluster for VictoriaMetrics (time series) as described in [part #6](https://medium.com/p/aeedbf038511).

> ⚠️ You must configure a dedicated storage for VictoriaMetrics ON ALL YOUR DEVICES by running the following commands
>
> If not already done
```bash
sudo mkdir -p /data/victoriametrics
sudo chown root:root /data/victoriametrics
sudo chmod 777 /data/victoriametrics
```

1) Import the VictoriaMetrics images

```bash
cd ../commons
sudo ./import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name victoriametrics/vminsert --image-version v1.119.0-cluster
sudo ./import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name victoriametrics/vmstorage --image-version v1.119.0-cluster
sudo ./import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name victoriametrics/vmselect --image-version v1.119.0-cluster
sudo ./import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name victoriametrics/vmauth --image-version v1.119.0
```

2) To make Telegraf able to publish into VictoriaMetrics, run the commands 

```bash
cd telegraf
sudo ./update-telegraf-level0.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT>
```

> ⚠️ This required to make the instances of level0 work with Victoriametrics.

3) Check if the configuration ```vmauth-config.yml``` exists with the command ```sudo docker config ls```

If not, go to the folder ```part4``` import it by typing the following commands

```bash
cd 4-0/data
sudo docker config create vmauth-config.yml ./auth.config.yml
```

4) Then update the stack ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:<LOCAL_REGISTRY_PORT> docker stack deploy --compose-file docker-compose.yml iot-stack --with-registry-auth```

To check the installation, please check the [list of the useful commands](../../docker-swarm-useful-commands.md).

---
# Troubleshootings

If you face any issues, please refer to this [page](../../docker-swarm-troubleshooting.md).
