[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)
[![Language](https://img.shields.io/badge/language-objective--c-lightgrey)]()
[![Release](https://shields.io/github/v/release/sveinbjornt/sloth?display_name=tag)]()
[![Build](https://github.com/sveinbjornt/sloth/actions/workflows/macos.yml/badge.svg)]()

# Sloth

<img src="resources/sloth_icon.png" width="192" height="192" align="right" style="float: right; margin-left: 30px;">

**Sloth** is a native Mac app that shows all open files, directories, sockets, pipes, and devices in use by all running processes on your system. This makes it easy to inspect which apps are using which files, etc.

* View all open files, directories, IP sockets, devices, Unix domain sockets, and pipes
* Filter by name, access mode, volume, type, location, or using regular expressions
* Sort by process name, file count, type, process ID, user ID, Carbon PSN, bundle UTI, etc.
* View IP socket status, protocol, port and version
* View sockets and pipes established between processes
* Inspection window with detailed macOS and Unix file/socket/process info
* Powerful contextual menu for file operations
* In-app authentication to run with root privileges
* Very fast, responsive native app written in Objective-C/Cocoa

Sloth is essentially a friendly, exploratory graphical user interface built on top of the  [`lsof`](https://en.wikipedia.org/wiki/Lsof) command line tool. The output of `lsof` is parsed and shown in a sortable, searchable outline view with all sorts of convenient additional functionality. Check out the screenshots below.

## Download

<a href="https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=BDT58J7HYKAEE"><img align="right" src="https://www.paypalobjects.com/WEBSCR-640-20110306-1/en_US/i/btn/btn_donate_LG.gif" ></a>

Sloth is free, open source software and has been continuously developed and maintained for a very long time (since 2004).
**If you find this program useful, please [make a donation](https://sveinbjorn.org/donations).**

*  **[⇩ Download Sloth 3.2](https://sveinbjorn.org/files/software/sloth.zip)** (~1.3 MB, Universal ARM/Intel 64-bit, macOS 10.9 or later)

Sloth can also be installed via [Homebrew](https://brew.sh) (may not be the latest version):

```shell
brew install --cask sloth
```

Old versions supporting macOS 10.8 and earlier can be downloaded [here](https://sveinbjorn.org/files/software/sloth/).


## Screenshots

#### View open files

<a href="resources/sloth_screenshot1.jpg">
<img src="resources/sloth_screenshot1.jpg" align="center" alt="Sloth Screenshot 1 - Files">
</a>

#### View IP sockets

<a href="resources/sloth_screenshot2.jpg">
<img src="resources/sloth_screenshot2.jpg" align="center" alt="Sloth Screenshot 2 - IP Sockets">
</a>

#### View sockets and pipes between processes

<a href="resources/sloth_screenshot3.jpg">
<img src="resources/sloth_screenshot3.jpg" align="center" alt="Sloth Screenshot 3 - Pipes and Unix Sockets">
</a>

## Build

Sloth can be built using a reasonably modern version of Xcode via the `xcodeproj` or by running the following command in the repository root (requires Xcode build tools):

```
make
```

Built products are created in `products/`.

## BSD License 

Copyright (c) 2004-2023 Sveinbjorn Thordarson
&lt;<a href="mailto:sveinbjorn@sveinbjorn.org">sveinbjorn@sveinbjorn.org</a>&gt;

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this
list of conditions and the following disclaimer in the documentation and/or other
materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may
be used to endorse or promote products derived from this software without specific
prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

The Sloth application icon is copyright (C) [Drífa Thoroddsen](https://drifaliftora.is).
