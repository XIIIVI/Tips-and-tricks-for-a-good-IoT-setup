This section handles some cybersecurity concerns as detailed in this [post](https://medium.com/p/74949dd03941).

Update/deploy the stack ```sudo PRIVATE_REPO=<IP_ADDRESS_OF_THE_REPO>:<LOCAL_REGISTRY_PORT> docker stack deploy --compose-file docker-compose.yml iot-stack```

To check the installation, please check the [list of the useful commands](../../../docker-swarm-useful-commands.md).

---

# Installation of the Grafana's dashboards

1) install Grizzly with the script ```chmod +x ./install_grizzly.sh && ./install_grizzly.sh```,

2) Logged as an admin in Grafana, create a service account token as described [here](https://medium.com/p/157166dce55d) (Section "Service account"),

3) Copy the generated token in the following code snippet, update the Grafana's URL

```bash
    grr config set grafana.url "http://<IP_OF_AN_ORCHESTRATOR>:8080/"
    grr config set grafana.token "<MY_NEW_TOKEN>"
    grr config set targets Datasource,DashboardFolder,LibraryElement,Dashboard,AlertRuleGroup,AlertNotificationPolicy,AlertContactPoint,AlertNotificationTemplate
    grr config set output-format json
```

4) Copy/paste those lines in the prompt,

5) Move to the folder `part9` and then type the command `grr push ./part9/grizzly`, the result should look like this

![alt text](images/grr-push.png)

---

# Dev version vs production version

The file docker-compose.yml is the development version of the Swarm's configuration.

The file docker-compose-secured.yml applies all the principles described in the post.

To test if your swarm is secured or not, run the script `sudo ./test-secured-swarm.sh --docker-compose <YOUR_DOCKER_COMPOSE_FILE>`

---

# Troubleshootings

If you face any issues, please refer to this [page](../../../docker-swarm-troubleshooting.md).
