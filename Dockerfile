FROM debian:latest

# Docker variables
ARG UID=1000
ARG GID=1000
ARG TARGETPLATFORM

# Replace default shell
RUN rm /bin/sh && ln -s bash /bin/sh

# Update packages
RUN DEBIAN_FRONTEND=noninteractive apt -qq -y update && \
    DEBIAN_FRONTEND=noninteractive apt -qq -y --no-install-recommends --no-install-suggests upgrade && \
    DEBIAN_FRONTEND=noninteractive apt -qq -y --no-install-recommends --no-install-suggests install \
    ## Add user package
    gawk wget git-core diffstat unzip texinfo libtinfo5 \
    build-essential chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 libegl1-mesa libsdl1.2-dev \
    pylint3 xterm vim telnet \
    ## Build kernel
    bc bison flex device-tree-compiler \
    ## Extra pkg
    locales tmux screen libncurses5-dev \
    ## For building poky docs
    make xsltproc docbook-utils fop dblatex xmlto \
    ## Install kas
    && pip3 install kas

# RUN command for specific target platforms
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ] ; \
     then apt-get install -y gcc-multilib ; \
     fi

# Clean up
RUN rm -rf /var/lib/apt/lists/*

# Setup the environment
RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.UTF-8

# Copy Morello /usr/bin files
COPY usr/bin/morello /usr/bin
RUN chmod u+x /usr/bin/morello
COPY usr/bin/morello-run.sh /usr/bin
RUN chmod a+x /usr/bin/morello-run.sh

# Clone the relevant repositories
RUN mkdir -p /usr/share/morello/images
RUN git clone https://git.morello-project.org/morello/fvp-firmware.git /usr/share/morello/fvp-firmware
RUN wget -qO- https://git.morello-project.org/morello/morello-linux-docker/-/jobs/artifacts/morello/mainline/raw/morello-fvp.tar.xz?job=build-morello-linux-docker | tar -xJf - -C /usr/share/morello/images

WORKDIR /morello
VOLUME [ "/morello" ]

# Create logs directory
RUN mkdir -p /morello/logs

COPY shell-env.sh /
RUN chmod u+x /shell-env.sh
ENTRYPOINT ["sh","/shell-env.sh"]
