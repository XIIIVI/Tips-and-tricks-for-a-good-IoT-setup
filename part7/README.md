This section provides a convenient way to build a hierarchy of log collectors as explained in [part #7](https://medium.com/p/63a3b9399d6c).

> ⚠️ You must configure a dedicated storage for Alloy ON ALL YOUR DEVICES by running the following commands
>
```bash
sudo mkdir -p /data/alloy
sudo chown root:root /data/alloy
sudo chmod 744 /data/alloy
```

❓Type ```./alloy/build-alloy-image.sh```


1) Import the Alloy image

```bash
sudo ../../commons/import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name grafana/alloy --image-version v1.9.1
```

2) Build and customize the Alloy image

```bash
cd alloy
chmod +x build-alloy-image.sh
sudo ./build-alloy-image.sh --local-registry-address <LOCAL_REGISTRY_IP_ADDRESS>
```

3) Then update the stack ```PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:4443 sudo docker stack deploy --compose-file docker-compose.yml iot-stack```
