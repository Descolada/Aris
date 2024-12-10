# ARIS
AutoHotkey Repository Install System

## Why use Aris
Compared to other package managers Aris is able to install from more sources: GitHub repositories,  Gists, archives (zip, tar files), and AutoHotkey forums posts. There is also a central index of packages which helps to find and install useful packages. 

Additionally, package.json isn't required to install a package, which greatly increases the number of places from where packages may be installed.

Furthermore, Aris doesn't require admin access nor does it use any other executables than AutoHotkey. For command line use there needs to be privileges to execute .bat files, this requirement might be removed in the future if it turns out to be an issue.

Most of the following examples will use the command line interface, but most packages can be installed via the GUI as well. Run Aris.ahk, select your project folder by pressing "Load package", then press "Add" in the "Current package" tab to install from a custom source.

## Introductory example
For example, to install my (Descolada) OCR package:
1. Run Aris.ahk, select your project folder, choose the Index tab, and double-click "Descolada/OCR"
2. Alternatively open command prompt or Powershell, navigate to your project folder, run `aris i Descolada/OCR`. Note: the Aris GUI needs to be started at least once before this, otherwise Aris isn't added to PATH.

Then either use the generated #include directive (in this case `#include <Aris/Descolada/OCR>`) or include all installed packages with `#include <packages>`

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

`aris update` without specifying a package tries to update the package in the working directory. For example, this could be used to update Aris itself.
### List
`aris list` lists all installed packages.
### Clean
`aris clean` removes unused entries from package.json dependencies and packages.ahk

# Examples

## Index install
Open the Aris GUI, then in the Index tab select a package and press "Install" (or double-click the package). Specific versions of packages can be installed by pressing the "Query versions" button.

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
It's also possible to create separate packages for specific files in a repository by using `-m`/`--main` and `--files` flags. The following example installs a single file and creates a package named "thqby/MCode":
```
aris i thqby/ahk2_lib as MCode --files MCode.ahk
```
Or include a folder (creates a package named "thqby/RapidOcr.ahk"):
```
aris i thqby/ahk2_lib as RapidOcr -m RapidOcr/RapidOcr.ahk --files RapidOcr/*.*
```
If a release has multiple assets then the fallback is the source zip file. However, if a specific asset is required then it can be specified in the version metadata (wildcards are supported):
```
aris i Descolada/OCR@latest+OCR.7z
```
## Gist install
Install a specific file from a Gist:
```
aris i https://gist.github.com/anonymous1184/7cce378c9dfdaf733cb3ca6df345b140/GetUrl.ahk
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

# Developer info

## Adding packages to index
The minimum information for an index.json entry is "description", "main", and "repository". If the package consists of more than a single file and not all files in the package are needed, then the "files" array should be filled with the appropriate file names or wildcard patterns. In that case "main" also needs to be specified with the relative path to the file, but doesn't need to be duplicated in the "files" array. 
Including a GitHub repo branch name is optional and will default to the default branch.

Example minimal entry, which downloads all files in the repository and sets main.ahk as the entry-point. "files" is implicitly ["*.*"] in this case.
```
	"Author/Name": {
		"description": "A short package description",
		"main": "main.ahk",
		"repository": "Author/repo[/branch]"
	}
```
Example multiple files minimal entry, which downloads the assets folder, include.ahk and main.ahk:
```
	"Author/Name": {
		"description": "A short package description",
		"main": "subfolder/main.ahk",
        "files": ["subfolder/include.ahk", "subfolder/assets/*.*"]
		"repository": "Author/repo/branch"
	}
```

# Roadmap
Not in order of priority:
1. Updating a main package (eg Aris itself) is currently untested, most likely needs fixing.
2. Improve GUI experience (beautify, search packages by tags etc)
3. Create automated tests
4. Support GitHub installs by tags
5. Support installs from local files/folders
6. Fix nested dependency installs in the case where specific versions are required