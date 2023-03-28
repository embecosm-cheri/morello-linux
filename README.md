# Introduction

## Docker image for Morello Linux based on Debian.

This page contains some simple instructions to get you started on Morello. In less than 10 minutes you should be able to setup a docker container with everything you need to build and boot into a Morello Debian environment on a Fixed Virtual Platform (FVP: https://developer.arm.com/downloads/-/arm-ecosystem-fvps).

**To set it up please follow the instructions below.**

**Note:** This approach does not require a Morello Board.

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
$ ./FVP_Morello.sh --force --destination ./FVP_Morello
...

Please answer with one of: 'yes' or 'no/quit'
Do you agree to the above terms and conditions? yes

```

Then, bring up the container (from workspace/):
```
$ docker-compose up -d
```

To run the Morello Linux image on the FVP, login into the container as user with id '1000' and run the command:

```
$ docker exec -it -u 1000 morello-linux /bin/bash
```

And then inside the docker:

```
# morello
```

Have a lot of fun!

**Note:** The first boot of the FVP model can take 5-10 minutes depending on the underlying hardware.

## Booting Debian on the FVP Model

In GRUB select the following option:

```
Debian Morello FVP (Device Tree)
```

When the boot process is complete insert the following user credentials:

```
Username: root
Password: morello
```

## Shutdown the FVP Model

To shutdown the FVP correctly type on a root shell:

```
$ shutdown -h now
```

To exit from the FVP Model press **Ctrl + ]** to access the telnet shell and then:

```
telnet> quit
```

## Cleanup the morello-linux container

To recover the space used by the morello-linux container execute the following commands:

```
$ docker stop morello-linux
$ docker image rm git.morello-project.org:5050/morello/morello-linux/morello-linux:latest -f
$ docker image prune
```

For further information please refer to the [Docker](https://docs.docker.com/) documentation.