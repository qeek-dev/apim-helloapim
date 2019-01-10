# Hello APIM 
This is a demo qpkg that how to integrate the API Manager.

# Prepare
* A unix base build machine, example: Ubuntu / Mac.
* Install the `Docker` in this build qpkg machine.
* The NAS installed the API Manager.

# How to build qpkg and install to NAS.
Run the `./build_qpkg.sh` script in the build machine. It will build the `hello-apim` qpkg and install it to the NAS.
```
./build_qpkg.sh {CPU_ARCH} {QPKG_VERSION} {NAS_IP} {NAS_PASSWD}
ex: ./build_qpkg.sh x86_64 0.1 192.168.0.10 passw0rd
CPU_ARCH: x86_64, arm_64, arm-x41, arm-x31 ...
```

# Directory layout
```
.
|-- QDK                         (git submodule of QDK, The version that support API Manager)
|-- README.md                   (Readme document)
|-- build_qpkg.sh               (QPKG build script of Hello APIM)
|-- qdk-docker                  (Docker image source, The environment could run the QDK)
|   |-- Dockerfile.build-stage
|   `-- Dockerfile.run-time
|-- release                     (QPKG files generated by the build script)
|-- src                         (Source code of Hello APIM)
|   |-- asset
|   |   |-- apim
|   |   |   `-- apim.json       (Registered the Hello APIM backend Http/WebSocket API by this file)
|   |   `-- qpkg                (QDK files for Hello APIM)
|   |       |-- icons
|   |       |-- package_routines
|   |       `-- qpkg.cfg
|   |-- init.d
|   |   `-- hello-apim.sh        (QPKG service script)
|   |-- server                  (Backend source code)
|   |   |-- go.mod
|   |   |-- go.sum
|   |   `-- main.go
|   `-- web                     (Frontend source code)
|       `-- index.html
`-- working                     (Temp directory for the build stage)
```