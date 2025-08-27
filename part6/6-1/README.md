This section provides a convenient way to build a cluster for VictoriaMetrics (time series) as described in [part #6](https://medium.com/p/aeedbf038511).

This version is based on replicated volumes managed with GlusterFS. GlusterFS is a fast shared filesystem that can keep the container volume in sync.

1) Set up replicated volumes

To create the replicated volumes, use the script `create-replicated-disks.sh` that will create the disks on all the host whose hostname start with a given prefix (e.g "orchestrator").

> :warning: This script does not work if hosts have the same hostname (e.g undefined).

| Parameter | Default value | Description |
|--|--|--|
| `login` | - | The login to use with SSH calls |
| `manager-hostname-prefix` | orchestrator | The prefix to check in the hostname |
| `password` | - | The password to use with SSH calls |
| `subnet` | - | The first 3 numbers of your subnet (e.g 192.168.1) |
| `volume-name` | gfs | The name of GlusterFS volume |

>:warning Create the folder `victoria-metrics` in `/mnt`: `sudo mkdir -p /mnt/victoria-metrics`

2) Import the VictoriaMetrics images

```bash
cd ../../commons
sudo ./import-image-into-local-repo.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS> --local-registry-port <LOCAL_REGISTRY_PORT> --image-name victoriametrics/victoria-metrics --image-version v1.122.0
```

3) To make Telegraf able to publish into VictoriaMetrics, run the commands 

```bash
cd telegraf
sudo ./update-telegraf-level0.sh --local-registry-address <LOCAL_REGISTRY_ADDRESS>
```

> ⚠️ This required to make the instances of level0 work with Victoriametrics.

4) Then update the stack ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:4443 docker stack deploy --compose-file docker-compose.yml iot-stack --with-registry-auth```

To check the installation, please check the [list of the useful commands](../../docker-swarm-useful-commands.md).

---
# Troubleshootings

If you face any issues, please refer to this [page](../../docker-swarm-troubleshooting.md).
