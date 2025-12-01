This is based off of: https://github.com/bokysan/docker-postfix/tree/v4.4.0

I have simply stripped away a lot of the unnecessary files and focused purely on what's being required in dockerfile.

I have also included the kubernetes manifest with mounts to isolate usage

* Generates an image for postfix
* sample manifests
* workflow to upload to ACR
