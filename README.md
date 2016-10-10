# os-image-builder
####Table of Contents

1. [Overview](#overview)
2. [Requirements](#requirements)
3. [Configuration](#configuration)
4. [Usage](#usage)

##Overview

os-image-builder creates OS installation ISO image based on Ubuntu CD for offline installation of Managed Services appliances.

##Requirements

The image builder is known to work on Ubuntu, so it is suggested to use this distribution on your build host.
You also need to download and install the following tools:
 * Packer image building tool (https://www.packer.io/docs/installation.html)
 * GnuPG (sudo apt-get install gnupg)
 * QEMU machine emulator and virtualizer (sudo apt-get install qemu-system-x86)
 
##Configuration

Before running the image builder for the first time please generate a new key pair:

~~~
$ gpg --gen-key
~~~

Follow the prompts to specify your name, email, and other items.

Make sure you can find pubring.gpg and secring.gpg files under $HOME/.gnupg directory. Also, you should be to see your newly generated keys by issuing `gpg -k` and `gpg -K` commands to list keys from the public and secret keyrings accordingly.

Open `base.json` in your favorite text editor and find `variables` section at the top of the file, you may need to modify some parameters there. The following parameters are available:
 * `iso`: specifies a file system path to the official Ubuntu installation CD image
 * `iso_md5`: MD5 hash of the installation CD image
 * `preseed`: specifies a file system path to a custom preseed file to be used for the installation (`config/custom.seed` is used by default)
 * `gpg_pubring`: path to pubring.gpg file
 * `gpg_secring`: path to secring.gpg file
 * `gpg_uid`: user id of your key (`gpg -k` command can be used to retrieve it)
 * `deb_packages`: a list of extra deb packages to be included into the pool structure of your target image (note that these packages won't be installed unless you specify them in a custom preseed file too)
 * `py_packages`: a list of Python packages to be included into the PyPI repository on the target image  (note that these packages won't be installed unless you specify them in `d-i preseed/late_command` of your custom preseed file)
 * `dst_iso`: specifies a file system path to the target ISO image

##Usage

Simply run `packer build base.json` command from the project directory and wait until it's done.


For Mac OS:

~~~
$ brew install packer
~~~
~~~
$ packer build -only virtualbox-iso centos7_gluster.json
~~~
(virtualbox shouols be installed)

