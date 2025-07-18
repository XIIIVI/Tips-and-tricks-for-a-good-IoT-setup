The script **create_swarm.sh** creates and configures both managers and workers.

> :warning: This script must be executed with `sudo`.

It uses a JSON file as a configuration file. When configuring each nodes, it takes in charge the Docker installation, hostname settings and even SSD1306 displays from [Uctronics](https://www.uctronics.com/download/Amazon/U6143_Manual.pdf?srsltid=AfmBOorkfytPr7klwMuoJBEXmr1BwNof1r0O-7JbS5iHn3ylYz1aS9aB).

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

## Configuration files `configurations`

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