# Hello APIM 
This is a demo qpkg that how to integrate the API Manager. Use QDK (Support API Manager) to pack this demo qpkg.

# Prepare
* A unix base build machine, example: Ubuntu / Mac.
* Install the `Docker` in this build qpkg machine.
* The NAS installed the API Manager.

# How to build qpkg and install to NAS.
Run the `./build_qpkg.sh` script in the build machine. It will build the `hello-apim` qpkg and install it to the NAS.
```
./build_qpkg.sh {CPU_ARCH} {NAS_IP} {NAS_PASSWD} {CODESIGNING_TOKEN} {QPKG_VERSION}
ex: ./build_qpkg.sh x86_64 192.168.0.10 passw0rd 3c70dd0d50f34ac082ba6349dfd01111
CPU_ARCH: x86_64, arm_64, arm-x41, arm-x31 ...
```

code signing token generate by QDK scripts.
```
$ working/QDK/scripts/codesigning_login.sh
```

# Directory layout
```
.
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
|   |       |-- buld_sign.csv   (Protection file list)
|   |       |-- package_routines
|   |       `-- qpkg.cfg
|   |-- init.d
|   |   `-- hello-apim.sh       (QPKG service script)
|   |-- server                  (Backend source code)
|   |   |-- go.mod
|   |   |-- go.sum
|   |   `-- main.go
|   `-- web                     (Frontend source code)
|       `-- index.html
`-- working                     (Temp directory for the build stage)
```