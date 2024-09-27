# ARIS
AutoHotkey Repository Install System

## Why use Aris
Compared to other package managers Aris is able to install from more sources. Package.json isn't necessary to install a package, instead just a GitHub repo can be specified. Aris is also able to install Gists, archives (zip, tar files), and AutoHotkey forums posts. There is also a central index of packages which helps to find and install useful packages.

Additionally, Aris doesn't require admin access nor does it use any other executables than AutoHotkey. For command line use there needs to be privileges to execute .bat files, this requirement might be removed in the future if it turns out to be an issue.

Most of the following examples will use the command line interface, but most packages can be installed via the GUI as well. Run Aris.ahk, select your project folder by pressing "Load package", then press "Add" in the "Current package" tab to install from a custom source.

## Introductory example
For example, to install my (Descolada) OCR package:
1. Run Aris.ahk, select your project folder, press "Add" and type "Descolada/OCR" (without quotes), press OK. 
2. Open command prompt or Powershell, navigate to your project folder, run `aris i Descolada/OCR`. Note: the Aris GUI needs to be started at least once before this, otherwise Aris isn't added to PATH.

Then either use the generated #include directive or include all installed packages with `#include <packages>`

## Aris command arguments
### Install
`aris install package` installs the specified package from the specified source, see examples further down.
Command aliases: `i`
`aris install Author/Name` will install either from the index, or the corresponding GitHub repo.
`aris i package@version` installs the specified version. If the package is already installed then it's forcibly uninstalled and then reinstalled with the specific version. Use @latest to install the latest version.
### Remove
`aris remove package` removes the package. Specify either the full package name, or only the name without the author.
Command aliases: `uninstall`, `r`, `rm`
### Update
`aris update package` updates to the latest allowed version specified in the package.json file. If the version is a hash then update to the latest version with `aris install package@latest`
### List
`aris list` lists all installed packages.
### Clean
`aris clean` removes unused entries from package.json dependencies and packages.ahk

# Examples

## Index install
Open the Aris GUI, then in the Index tab select a package and press "Install". Specific versions of packages can be installed by pressing the "Query versions" button.

Install via the command line by specifying the full package name, or if there is only one package with the package name then only that may be used.

For example, install UIA-v2 with
```
aris i UIA
```
or
```
aris i Descolada/UIA
```

## GitHub install
GitHub installs first checks for releases and downloads the latest one, and if no releases are found then falls back to the latest commit.
Use the full URL:
```
aris i https://github.com/Descolada/OCR
```
Or short forms:
```
aris i github:Descolada/OCR
```
A specific branch may be requested:
```
aris i gh:Descolada/OCR/main
```
A specific release version may be requested:
```
aris i gh:Descolada/UIA-v2@v1.0.0
```
A specific commit short-hash may be requested:
```
aris i gh:Descolada/OCR@1ef23ba
```
If the package isn't in the package index, then by default it's assumed a GitHub repo:
```
aris i Descolada/OCR
```
It's also possible to create separate packages for specific files in a repository by using `-m`/`--main` and `--files` flags. To install a single file (creates a package named "thqby/MCode.ahk"):
```
aris i thqby/ahk2_lib -m MCode.ahk
```
Or include a folder (creates a package named "thqby/RapidOcr.ahk"):
```
aris i thqby/ahk2_lib -m RapidOcr/RapidOcr.ahk --files RapidOcr/*.*
```
## Gist install
Install a specific file from a Gist:
```
https://gist.github.com/anonymous1184/7cce378c9dfdaf733cb3ca6df345b140/GetUrl.ahk
```
Short form can be used:
```
aris i gist:7cce378c9dfdaf733cb3ca6df345b140/GetUrl.ahk
```
If the file name is omitted, then the first available file is used:
```
aris i gist:7cce378c9dfdaf733cb3ca6df345b140
```

## Forums install
Forums install queries the webpage from Wayback Archive, which might not have the latest page content and is usually also quite slow to respond (installs may take tens of seconds). However, it allows for versioning in the form of the date the web page was crawled.

To install from a forums post, use the URL of the thread. Required URL field is "t=123456" (the thread id), optional are "codebox=1" (the code box number on the page, by default is 1), "p=123456" (post id) and "start=123" (is related to the page in the thread). Note that the Wayback Machine reliably only has the main page of the thread.
```
aris i https://www.autohotkey.com/boards/viewtopic.php?f=83&t=116471
```
To install directly from the AutoHotkey forums use @latest. This does not work if the forums has Cloudflare attack mode activated (which causes the "verify you are human" page to appear).
```
aris i https://www.autohotkey.com/boards/viewtopic.php?f=83&t=116471@latest
```

## Archive install
For archive installs use the download URL. A version can't be specified in this case.
```
aris i https://github.com/Descolada/UIA-v2/archive/refs/heads/main.zip
```

# Roadmap
1. Updating a main package (eg Aris itself) is currently untested, most likely needs fixing.
2. Add global install support (currently only local installs)
3. Add package name aliases support
4. Improve GUI experience (beautify, make GUI resizable, search packages by tags etc)
5. Create automated tests