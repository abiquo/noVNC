noVNC
=====

Files to run noVNC in Abiquo

## Installer

Installs proxy and/or sets up UI.

### Install proxy

```
# installer.sh -w -l 41337 -a https://server/api -u admin -p xabiquo -c some.crt -k some.key
```

- ```-w``` Flag to install proxy or not.
- ```-l``` Port where the proxy will listen. Defaults to 41337.
- ```-a``` Abiquo API URL.
- ```-u``` Abiquo API user.
- ```-p``` Abiquo API pass.
- ```-c``` If set, will be the cert used by the proxy.
- ```-k``` If ```-c``` is set, this is the key matching the cert.

### Setup UI

```
# installer.sh -i proxy_addres:41337
```

- ```-i``` Address where the proxy is listening [IP or hostname]:[PORT]
