# cicd-tools
This repository contains a collection of CI/CD tools/scripts that are primarily used in closed environments such as local servers.

## build_check.sh
This script is a tool to do a build check of a cmake based github repository. It first checks the build status of the github action of the specified github repository. In case of valid checks it will proceed to fetch the latest changes and starts the configuring process of cmake followed by starting the compile process with make. If any of the processes fail to run successfully the script will stop and print out the error log in /tmp/build_check.log (default location)

How to use:

Put this script or a symbolic link of it in your preferred
location and adjust the setup in the script itself. Make it executable
and run it:

```shell
chmod +x build_check.sh
./build_check.sh
```
### Further configuration without modification

GITHUB_REPO="Hansi/Wurstbrot" REPO_DIR="/home/hansi/$(basename "$GITHUB_REPO")" BUILD_DIR="$REPO_DIR/build" RECIPIENTS="wurst@hans.com" LOG_FILE="/tmp/build_wurstbrot_check.sh" ./bin/build_check.sh