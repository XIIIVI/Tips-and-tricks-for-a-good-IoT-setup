This section provides a convenient way to build the Telegraf images per level.
As described in this [post](https://medium.com/p/394ebabea7), we limit the depth to 3 levels (from 0 to 2).

> ⚠️ You must configure a dedicated storage for Telegraf ON ALL YOUR DEVICES by running the following commands
>
```bash
sudo mkdir -p /data/telegraf
sudo chown root:root /data/telegraf
sudo chmod 744 /data/telegraf
```

1) Import the Telegraf image

```bash
sudo ../../commons/import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name telegraf --image-version 1.34.4-alpine
```

2) Build the customized Telegraf images

```bash
chmod +x ./build-telegraf-images.sh
sudo ./build-telegraf-images.sh --local-registry-address <LOCAL_REGISTRY_IP_ADDRESS> --level-number 0
sudo ./build-telegraf-images.sh --local-registry-address <LOCAL_REGISTRY_IP_ADDRESS> --level-number 1
sudo ./build-telegraf-images.sh --local-registry-address <LOCAL_REGISTRY_IP_ADDRESS> --level-number 2
```
