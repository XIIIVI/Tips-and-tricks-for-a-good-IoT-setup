The script **create_swarm.sh** creates and configures both managers and workers of a Docker Swarm.

> :warning: This script must be executed with `sudo` on a device where Docker has been previously installed.

> :warning: All the hosts should have the same default login and password for an automatic deployment.

> :warning: All the hosts should support an SSH access based on credentials.

:warning::warning::warning: THE SWARM CREATION AND CONFIGURATION IS A LONG RUNNING PROCESS (Around 35mn for 4 devices):warning::warning::warning:

It uses a JSON file as a configuration file. When configuring each nodes, it takes in charge 
* the Docker installation, 
* Chrony installation (NTP server),
* DCV installation (Docker Viewer Image),
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

### Managers

This section details the node `managers`used to automatically create the managers of the swarm.

```json
        "managers": {
            "hostname-default-prefix": "orchestrator",
            "members": [
                {
                    "ip-address": "192.168.2.191",
                    "folders": [
                        "/data/alloy",
                        "/data/database",
                        "/data/mosquitto/config",
                        "/data/mosquitto/data",
                        "/data/mosquitto/log",
                        "/data/telegraf/logs"
                    ],
                    "labels": [
                        {
                            "key": "mqtt",
                            "value": "true"
                        },
                        {
                            "key": "level",
                            "value": "0"
                        }
                    ],
                    "has-display": true
                },
                ...
            ]
        }
```

`hostname-default-prefix` is the default prefix to use when setting the hostname. The index (starting from 1) of the item in the array `members` is appended to this prefix.

`labels` is an array of keypair values used as labels of the node.

`has-display` if set to `true`, the script will install all the needed packages to display a message on the SSD1306 display.

`members` is an array of manager's configurations.

For each item,

`ip-address` is the IP address of the host, mainly used with `ssh` to log on.

`folders` defines the list of folders to create. :warning: Please note that the permission 777 is applied to each folder. To have fine-grained level of permission, refer to the section `Volumes` of this [chapter](https://medium.com/p/3af124734c42).

### Workers

This section details the node `workers`used to automatically create the workers of the swarm.

```json
        "workers": [
            {
                "ip-address": "192.168.2.118",
                "hostname": "sat1",
                "folders": [
                    "/data/alloy",
                    "/data/telegraf/logs",
                    "/data/telegraf/states"
                ],
                "labels": [
                    {
                        "key": "level",
                        "value": "1"
                    }
                ],
                "has-display": true
            }
        ],
```
`workers` is an array of workers.

For each item (worker),

`ip-address` is the IP address of the host, mainly used with `ssh` to log on.

`hostname` is the hostname. As by default, a swarm is a flat architecture, unlike the managers, the hostname of a worker must be explicitly set.

`folders`, `labels`and `has-display` have the same roles as the ones explained for the managers.

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
                    "key-and-csr": [ ... ]
                },
            ]
        }
    }
}
```

`name` is the name of the certificate and the name of the files containing the certificate authority (.ca), the server certificate (.crt) and the public key (.key).

`days-valid` is the number of days before before expiration.

`country` is the country where the certificate is delivered.

`state` is the state where the certificate is delivered.

`locality` is the city where the certificate is delivered.

`organization` is the organization delivering the certificate.

:warning: `key-and-csr` is an array of service names used to define the SAN (Subject Alternative Names) of the certificate used for TLS.

 

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

---

# Troubleshootings

❌ When I run the script, I got the following errors

```text
Error response from daemon: rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial tcp 192.168.2.192:2377: connect: connection refused"
Connection to 192.168.2.192 closed.
```

**Explanation:** you're running the script after an unsuccessful installation. The script is re-using information generated by the previous installation and stored in the files `join*.swarm`