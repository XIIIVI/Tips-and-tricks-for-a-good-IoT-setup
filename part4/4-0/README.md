The script **create_swarm.sh** creates and configures both managers and workers of a Docker Swarm.

> :warning: This script must be executed with `sudo`.

> :warning: All the hosts should have the same default login and password for an automatic deployment.

:warning::warning::warning: THE SWARM CREATION AND CONFIGURATION IS A LONG RUNNING PROCESS (Around 50mn for 5 devices):warning::warning::warning:

It uses a JSON file as a configuration file. When configuring each nodes, it takes in charge 
* the Docker installation, 
* hostname settings,
* SSD1306 displays from [Uctronics](https://www.uctronics.com/download/Amazon/U6143_Manual.pdf?srsltid=AfmBOorkfytPr7klwMuoJBEXmr1BwNof1r0O-7JbS5iHn3ylYz1aS9aB),
* creation of 
- the configurations,
- the credentials,
- the networks,
- the volumes.

---
# Parameters of the script

| Parameter | Description |
|--|--|
| `--configuration-file or -f`| The JSON file containing the definition of the Swarm |
| `--login` | The login to use when connecting with SSH to the device |
| `--password` | The password to use when connecting with SSH to the device |
| `--default-hostname` | This optional parameter is set by default to "undefined" and used to set the hostname of the node |

---
# Configuration file format

## `swarm`node

### Configuration files `configurations`

You can directly import configuration files thru the section `configurations`

 ```json
 {
    "swarm": {
        "managers": {
             ...
        },
        "workers": [
             ...
        ],
        "configurations": [
            {
                "name": ...,
                "file": ...
            }
        ]
    }
}
```

`name` is the name of the configuration file in the Swarm. this is the value to use when referencing the file.

`file` is the path to the file to import.

### Secrets

#### Credentials

You can add a file containing credentials thru the array `credentials` in the section `secrets`

```json
{
    "swarm": {
        "managers": {
             ...
        },
        "workers": [
             ...
        ],
        "secrets": {
           "credentials": [
                {
                    "name": "...",
                    "login": "..."
                }
            ],
            "certificates": [
               ...
            ]
        }
    }
}
```

`name`is the filename.

`login` is the account to use.

> :warning: The password is automatically generated for security reason.

#### Certificates

You can add a file containing credentials thru the array `credentials` in the section `secrets`

```json
{
    "swarm": {
        "managers": {
             ...
        },
        "workers": [
             ...
        ],
        "secrets": {
           "credentials": [
             ...
            ],
            "certificates": [
                {
                    "name": "...",
                    "days-valid": ...,
                    "country": "...",
                    "state": "...",
                    "locality": "...",
                    "organization": "...",
                    "common-name": "..."
                },
            ]
        }
    }
}
```

`name` is the name of the certificate and the name of the files containing the certificate (.crt) and the public key (.key).

`days-valid` is the number of days before before expiration.

`country` is the country where the certificate is delivered.

`state` is the state where the certificate is delivered.

`locality` is the city where the certificate is delivered.

`organization` is the organization delivering the certificate.

`common-name` is the common-name of the certificate.

### Volumes

As described in [part #6](https://medium.com/p/aeedbf038511), the array `volumes` takes in charge the creation and mounting of volumes for data storage/sharing.

```json
{
    "swarm": {
        "managers": {
             ...
        },
        "workers": [
             ...
        ],
        "volumes": [
            {
                "replicated": [
                    {
                        "name": "...",
                        "hosts": [ "...", ...,  ],
                        "folders": [ "...", ... ]
                    }
                ]
            }
        ]
}
```

The array `replicated`provides a convenient way to create a replicated GlusterFS storage across multiple host (managers and workers can be mixed).

`name` is the name of the volume (the mounting point is `/mnt/<name>`).

`hosts` is the list on hosts where the replicated storage must be installed.

`folders` is the list of folder to create in the folder `/mnt/mountpoint-subfolder`. Please note that **a volume will be created per folder**. The name of each volume is the concatenation of `name` and the folder name.

---
## Local Docker registry

If you are using a local registry in your LAN, you can add the node `registry` (same level `swarm`).

`ip-address` IP address of the local Docker registry

`port` The port used for HTTPS (e.g 4443 or 443)

`certificate-file` A copy of the certificate of the local Docker registry