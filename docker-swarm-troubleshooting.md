Troubleshootings

If the deployment does not work (CURRENT STATE set to Rejected), check this contraint 

⚠️ ON ALL THE CLIENTS, copy $REGISTRY_DIR/certs/registry.crt into /usr/local/share/ca-certificates/registry.crt

```bash

sudo mkdir -p /usr/local/share/ca-certificates/ && vi /usr/local/share/ca-certificates/registry.crt

sudo update-ca-certificates
sudo systemctl restart docker
sudo systemctl status docker

```
