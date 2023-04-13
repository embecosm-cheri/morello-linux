# Cosign and morello-linux

morello-linux generated containers are signed using [cosign](https://github.com/sigstore/cosign). To verify the validity of a container before downloading it you can use the commands below:
```
$ cosign verify --key cosign.pub git.morello-project.org:5050/morello/morello-linux/morello-linux

Verification for git.morello-project.org:5050/morello/morello-linux/morello-linux:latest --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - The signatures were verified against the specified public key
  - Any certificates were verified against the Fulcio roots.
[{"critical":{"identity":{"docker-reference":"git.morello-project.org:5050/morello/morello-linux/morello-linux"},"image":{"docker-manifest-digest":"sha256:e50b98871186ad76bc03cfd380d6c7cd3343cf28b15c836100c09d874462d505"},"type":"cosign container image signature"},"optional":null}]
```
The public key [cosign.pub](cosign.pub) can be retrieved from the same directory of this README.md file.