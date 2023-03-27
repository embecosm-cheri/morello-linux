# Introduction

Docker image for Morello Linux based on Debian.

# Setup

Install docker:
```
$ curl -sSL https://get.docker.com | sh
```

Install docker-compose:

Latest: v2.17.2

Installation command:
```
$ sudo curl -L "https://github.com/docker/compose/releases/download/v2.17.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
```

Provide correct permissions to docker compose:
```
$ sudo chmod +x /usr/local/bin/docker-compose
```

Test docker-compose:
```
$ docker-compose --version
```

# Usage

Create the following workspace structure:

```
workspace/
  |-> morello/
  |-> docker-compose.yml
```

Create a `docker-compose.yml` file and map the morello directory into /morello as follows:

```
# Docker composer file for Morello Linux
version: '3.8'
services:
  morello-linux:
    image: "git.morello-project.org:5050/morello/morello-linux/morello-linux:latest"
    container_name: "morello-linux"
    environment:
      - UID=1000
      - GID=1000
    volumes:
      - ./morello:/morello
    tty: true
    restart: unless-stopped
```

Install the Morello FVP model as follows:

```
$ cd morello
$ wget -O FVP_Morello_0.11_34.tgz https://developer.arm.com/-/media/Arm%20Developer%20Community/Downloads/OSS/FVP/Morello%20Platform/FVP_Morello_0.11_34.tgz?rev=5f34837ae6c14ede8493dfc24c9af397&hash=862883120C5638E0B3C5ACA6FDDC5558021E1886
$ tar -xzvf FVP_Morello_0.11_34.tgz
$ ./FVP_Morello.sh
...

(Follow the instructions)

...

Where would you like to install to? [default: /home/<user>/FVP_Morello] ./FVP_Morello

...

'<full path to morello directory>/./FVP_Morello' does not exist, create? [default: yes] yes (Enter)
```

Then, bring up the container (from workspace/):
```
$ docker-compose up -d
```

To build the Morello Linux image, login into the container as user with id '1000':

```
$ docker exec -it -u 1000 morello-linux /bin/bash
# morello
```

Have a lot of fun!