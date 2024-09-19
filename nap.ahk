#Requires AutoHotkey v2
;#include <packages>
#include <cJSON>
#include <ui-main>
#include <utils>

/*
    Installing a library should install it either in Lib or includes folder, whichever exists.
    Installation creates a packages.ahk file, which also acts as a lock file describing the exact dependencies needed.
    It should also create a package.json file to describe the range of dependencies allowed. This should
    be done automatically without needing user input, as most users simply want to use a library, not enter info
    about their own project.

    A library might have a package.json file, in which case it describes which dependencies need to be installed 
    in order for it to function, and it will not function otherwise. However, should it be even necessary?
    Because most creators will most likely try to make their library a complete package, not with external dependencies.
    In the future that might change though, if a package manager becomes popular enough.

    The index should contain short descriptive info about packages. Should it also include the dependencies?
    The problem is that if the package contains package.json and its dependency list is different, then
    we might get weird conflicts. This is why the index should only list dependencies for packages without a known
    package.json.

    The other way would be to *only* use index.json and not require package.json. In that case all info
    should be in index.json and updated if necessary. That could mean potential mismatches between
    info in the index and actual wants of the developers (eg licensing, dependencies etc).

    Possible use cases:
    1) Plain project (no package.json), install package without package.json. In this case we create
        package.json and packages.ahk, and the library will be stored in a lib folder.
    2) Package project, install package without package.json. Same as previous, just don't create package.json.
    3) Plain project, install package with package.json.
*/

/*
whr := ComObject("WinHttp.WinHttpRequest.5.1")
whr.Open("GET", "https://api.github.com/repos/Descolada/UIA-v2/commits", true)
whr.SetRequestHeader("Accept", "application/vnd.github+json")
whr.Send()
whr.WaitForResponse()
res := whr.ResponseText
*/

; Raw files:
; https://github.com/user/repository/raw/branch/filename
; https://github.com/user/repository/raw/{commitID}/filename
; https://github.com/{user}/{repo}/raw/{branch}/{path}
; https://raw.github.com/{user}/{repo}/raw/{branch}/{path}?token={token}


; Specific commit links:
; https://github.com/G33kDude/cJson.ahk/blob/fd89582/Dist/JSON.ahk
; https://github.com/G33kDude/cJson.ahk/raw/fd89582/Dist/JSON.ahk

; Branch links:
; https://github.com/G33kDude/cJson.ahk/blob/v2/Dist/JSON.ahk
; https://github.com/github/codeql/archive/refs/heads/main.tar.gz

; Release links:
; https://github.com/G33kDude/cJson.ahk/releases/tag/2.0.0/Dist/JSON.ahk
; https://github.com/G33kDude/cJson.ahk/releases/download/2.0.0/JSON.ahk


; Gist links:
; https://gist.github.com/raw/[ID]/[REVISION]/[FILE]

/*
    Possible install formats:
    PackageName             => queries index.json, otherwise fails
    Username/PackageName    => queries index.json, otherwise tries GitHub repo with the same name
    Addition of @version    => tries to match specified version range
    Addition of @ShortHash  => query for specific commit on repo
*/

global g_GitHubRawBase := "https://raw.githubusercontent.com/Descolada/NAP/main/", g_Index, g_Config := Map(), g_PackageJson, g_LastInstalledDependency := ""
global g_Switches := Map("global_install", false, "minimal_install", false, "force", false)
A_FileEncoding := "UTF-8"

;A_Args := ["install", "https://github.com/Descolada/UIA-v2/archive/refs/heads/main.zip"]
;A_Args := ["remove", "UIA-v2-main"]
;A_Args := ["install", "UIA"]
;A_Args := ["install", "UIA@1.0.1"]
;A_Args := ["update", "UIA"]
;A_Args := ["remove", "UIA"]
;A_Args := ["list"]
;A_Args := ["install", "Descolada/OCR@1ef23ba"]
;A_Args := ["install"]
;A_Args := ["install", "cJSON"]
;A_Args := ["update", "G33kDude/cJson@2.0.0"]
;A_Args := ["install", "CGdip"]
;A_Args := ["remove", "OCR"]
;A_Args := ["install", "crypt"]
;A_Args := ["install", "Descolada/OCR", "thqby/Crypt"]
;A_Args := ["remove", "Descolada/wInspector"]
;A_Args := ["install", "graphicsearch@0.5"]
;A_Args := ["update", "graphicsearch"]
;A_Args := ["remove", "graphicsearch"]

;A_Args := ["install", "gist:4bf163aa9a9922b21fbf/RawInput"]
;A_Args := ["remove", "RawInput"]


;result := QueryGitHubGist("4bf163aa9a9922b21fbf")

LoadPackageIndex()
g_PackageJson := LoadPackageJson()
LoadConfig()

if (!A_Args.Length) {
    Persistent()
    LaunchGui()
} else {
    command := "", targets := []
    for Arg in A_Args {
        switch Arg, 0 {
            case "install", "i", "remove", "update", "update-index", "list":
                command := Arg
            case "-g", "--global-install":
                g_Switches["global_install"] := true
            case "-m", "--minimal-install":
                g_Switches["minimal_install"] := true
            case "-f", "--force":
                g_Switches["force"] := true
            default:
                if !command
                    WriteStdOut("Unknown command. Use install, remove, update, or list.")
                else
                    targets.Push(Arg)
        }
    }
    switch command, 0 {
        case "install":
            if targets.Length {
                for target in targets
                    InstallPackage(target)
            } else {
                InstallPackageDependencies()
            }
        case "remove":
            if targets.Length {
                for target in targets
                    RemovePackage(target)
            } else
                WriteStdOut("Specify a package to remove.")
        case "update":
            if !FileExist(A_WorkingDir "\package.json")
                throw ValueError("Missing package.json, cannot update package", -1)
            if targets.Length
                for target in targets
                    InstallPackage(target,, true)
            ;InstallPackage(LoadPackageJson(A_WorkingDir)["name"], true, )
        case "update-index":
            UpdatePackageIndex()
        case "list":
            ListInstalledPackages()
    }
}

InstallPackageDependencies() {
    LibDir := FindLibDir()
    Dependencies := ParseInstalledPackages()
    if !Dependencies.Length {
        if FileExist(".\package.json") {
            PackageJson := LoadPackageJson()
            if PackageJson.Has("dependencies") {
                DependenciesMap := PackageJson["dependencies"]
                for Dependency, VersionRange in DependenciesMap
                    Dependencies.Push(ParsePackageName(Dependency "@" VersionRange))
            }
        }
    } else
        for i, Dependency in Dependencies
            Dependencies[i] := Dependency.PackageName "@" Dependency.Version
    if !Dependencies.Length {
        WriteStdOut "No dependencies found"
        return
    }
    for Dependency in Dependencies
        InstallPackage(Dependency)
}

UpdatePackage(PackageName) {
    LibDir := FindLibDir()
    PackageInfo := ParsePackageName(PackageName)
    InstalledPackages := ParseInstalledPackages()

    if !(Matches := FindMatchingInstalledPackages(PackageInfo, InstalledPackages))
        return

    if !Matches.Length
        return WriteStdOut("No matching installed packages found: `"" PackageName "`"")

    if Matches.Length > 1 {
        WriteStdOut "Multiple matches found:"
        for Match in Matches
            WriteStdOut "`t" Match.PackageName "@" Match.Version
    } else {
        try {
            if InstallPackage(Matches[1].PackageName "@" LoadPackageJson()[Matches[1].PackageName], false)
                WriteStdOut "Package successfully updated!"
        }
    }
}

InstallPackage(PackageName, IsMainPackage:=false, CanUpdate:=false) {
    Result := 0
    TempDir := "~temp-" Random(100000000, 1000000000)
    DirCreate(TempDir)

    if !IsSet(LibDir)
        LibDir := FindLibDir()

    Includes := ParseInstalledPackages()

    if IsMainPackage {
        try PackageInfo := ExtractPackageInfoFromNameAndIndex(PackageName)
        catch as err {
            WriteStdOut err.Message (err.Extra ? ": " err.Extra : "")
            goto Cleanup
        }
        PrevWorkingDir := A_WorkingDir
        try {
            VerifyPackageIsDownloadable(PackageInfo)
            if IsPackageInstalled(PackageInfo, Includes, [TempDir, LibDir])
                goto Cleanup
            FinalDirName := DownloadSinglePackage(PackageInfo, TempDir)
            A_WorkingDir := TempDir "\" FinalDirName
            Dependencies := Map()
            LibDir := FindLibDir()
            if FileExist(LibDir "\packages.ahk") {
                Dependencies := ParseInstalledPackages()
            } else if FileExist(".\package.json") {
                PackageJson := LoadPackageJson()
                if PackageJson.Has("dependencies")
                    Dependencies := PackageJson["dependencies"]
            } else {
                if g_Index.Has(PackageInfo.PackageName) && g_Index[PackageInfo.PackageName].Has("dependencies")
                    Dependencies := g_Index[PackageInfo.PackageName]["dependencies"]
            }
            if Dependencies.Count {
                for Dependency, Version in Dependencies
                    InstallPackage(Dependency "@" Version)
            }
            A_WorkingDir := A_WorkingDir
        } catch as err {
            WriteStdOut "Failed to download package"
            WriteStdOut "`t" err.Message (err.Extra ? ": " err.Extra : "")
            A_WorkingDir := PrevWorkingDir
            goto Cleanup
        }
    } else {
        try DownloadPackageWithDependencies(PackageName, TempDir, &Includes, IsMainPackage, CanUpdate)
        catch as err {
            WriteStdOut "Failed to download package with dependencies"
            WriteStdOut "`t" err.Message (err.Extra ? ": " err.Extra : "")
            goto Cleanup
        }
    }

    if IsMainPackage {
        DirMove(TempDir, A_WorkingDir, 2)
        LibDir := FindLibDir()
    } else
        DirMove(TempDir, LibDir, 2)

    if FileExist("package.json") {
        PackageJson := JSON.Load(FileRead("package.json"))
        if !PackageJson.Has("dependencies")
            PackageJson["dependencies"] := Map()
    } else {
        PackageJson := Map("dependencies", Map())
    }

    if FileExist(LibDir "\packages.ahk")
        IncludeFileContent := FileRead(LibDir "\packages.ahk")
    else
        IncludeFileContent := "; Avoid modifying this file manually`n`n"

    for Include in Includes {
        if !PackageJson["dependencies"].Has(Include.PackageName) {
            PackageJson["dependencies"][Include.PackageName] := (SubStr(Include.Version, 1, 1) ~= "\w" && !IsVersionSha(Include.Version)) ? "^" Include.Version : Include.Version
            if CanUpdate
                WriteStdOut 'Package successfully updated to "' Include.PackageName "@" Include.Version '"!'
            else
                WriteStdOut "Package successfully installed!"
        }
        if Include.HasProp("Main") && Include.Main {
            Addition := "#include .\" Include.InstallName "\" Include.Main "`n"
            if !InStr(IncludeFileContent, Addition)
                IncludeFileContent .= Addition
        }
    }

    if !PackageJson["dependencies"].Count
        PackageJson.Delete("dependencies")

    if !IsMainPackage
        FileOpen("package.json", 0x1).Write(JSON.Dump(PackageJson, true))
    FileOpen(LibDir "\packages.ahk", 0x1).Write(IncludeFileContent)

    Result := 1

    Cleanup:
    try DirDelete(TempDir, 1)
    return Result
}

DownloadPackageWithDependencies(PackageName, TempDir, &Includes, IsMainPackage:=false, CanUpdate:=false, MarkedForRemove:=[]) {
    global g_LastInstalledDependency
    try PackageInfo := ExtractPackageInfoFromNameAndIndex(PackageName)
    catch as err {
        WriteStdOut err.Message (err.Extra ? ": " err.Extra : "")
        return 0
    }
    IsVersioned := PackageInfo.Version || (PackageInfo.RepositoryType = "archive")

    if CanUpdate && !InStr(PackageName, "@") g_PackageJson["dependencies"].Has(PackageInfo.PackageName) {
        PackageInfo.Version := g_PackageJson["dependencies"][PackageInfo.PackageName]
    }

    if IsMainPackage {
        PrevWorkingDir := A_WorkingDir
        A_WorkingDir := TempDir
        goto DownloadPackage
    }

    LibDir := FindLibDir()

    ; First download dependencies listed in index.json, except if we are updating our package
    if !CanUpdate && PackageInfo.Dependencies.Count {
        for DependencyName, DependencyVersion in PackageInfo.Dependencies {
            if !DownloadPackageWithDependencies(DependencyName "@" DependencyVersion, TempDir, &Includes)
                throw Error("Failed to install dependency", -1, DependencyName "@" DependencyVersion)
        }
    }

    if !CanUpdate && PackageInfo.Version {
        for i, Include in Includes {
            if (Include.PackageName = PackageInfo.PackageName && (DirExist(TempDir "\" Include.InstallName) || DirExist(LibDir "\" Include.InstallName))) {
                WriteStdOut 'Package "' Include.InstallName '" already installed, skipping...'
                PackageInfo.InstallName := Include.InstallName, g_LastInstalledDependency := PackageInfo
                return Include
            }
        }
    }

    DownloadPackage:

    VerifyPackageIsDownloadable(PackageInfo)
    if IsPackageInstalled(PackageInfo, Includes, [TempDir, LibDir]) {
        if CanUpdate
            WriteStdOut 'Package "' PackageInfo.PackageName "@" PackageInfo.Version '" has no matching updates available'
        else
            WriteStdOut 'Package "' PackageInfo.PackageName "@" PackageInfo.Version '" is already installed'
        return 0
    }

    FinalDirName := DownloadSinglePackage(PackageInfo, TempDir)

    if !FinalDirName
        return 0

    if !IsVersioned {
        for i, Include in Includes {
            if (Include.PackageName = PackageInfo.PackageName && DirExist(LibDir "\" Include.InstallName)) {
                Includes.RemoveAt(i)
                InstalledPackages := ParseInstalledPackages()
                ForceRemovePackageWithDependencies(Include, InstalledPackages, LibDir)
                break
            }
        }
    } else if CanUpdate {
        for i, Include in Includes {
            if (Include.PackageName = PackageInfo.PackageName && DirExist(LibDir "\" Include.InstallName) && IsVersionCompatible(PackageInfo.Version, "^" Include.Version)) {
                ForceRemovePackage(Include, LibDir)
                Includes.RemoveAt(i)
                break
            }
        }
    }

    if PackageInfo.Files.Length {
        DirCreate(TempDir "\~" FinalDirName)
        if PackageInfo.Files.Length = 1 {
            FileName := Trim(StrReplace(PackageInfo.Files[1], "/", "\"), "\/")
            if PackageInfo.Main
                PackageInfo.Main := StrSplit(StrReplace(PackageInfo.Main, "/", "\"), "\")[-1]
            if DirExist(FileName)
                DirMove(TempDir "\" FinalDirName "\" PackageInfo.Files[1], TempDir "\~" FinalDirName, 2)
            else
                FileMove(TempDir "\" FinalDirName "\" PackageInfo.Files[1], TempDir "\~" FinalDirName "\" PackageInfo.Main)
        } else {
            for FileName in PackageInfo.Files {
                FileName := Trim(StrReplace(FileName, "/", "\"), "\/")

                DirName := "", SplitName := StrSplit(FileName, "\")
                if DirExist(FileName)
                    SplitName.Pop()
                for SubDir in SplitName
                    DirName .= SubDir "\", DirCreate(TempDir "\~" FinalDirName "\" DirName)

                if DirExist(FileName)
                    DirMove(TempDir "\" FinalDirName "\" FileName, TempDir "\~" FinalDirName "\" FileName, 1)
                else
                    FileMove(TempDir "\" FinalDirName "\" FileName, TempDir "\~" FinalDirName "\" FileName)
            }
        }
        if FileExist(TempDir "\" FinalDirName "\LICENSE")
            FileMove(TempDir "\" FinalDirName "\LICENSE", TempDir "\~" FinalDirName "\LICENSE")
        DirDelete(TempDir "\" FinalDirName, 1)
        DirMove(TempDir "\~" FinalDirName, TempDir "\" FinalDirName)
    }

    AddMainInclude:

    if !PackageInfo.Main {
        if FileExist(TempDir "\" FinalDirName "\main.ahk")
            PackageInfo.Main := "main.ahk"
        else if FileExist(TempDir "\" FinalDirName "\" PackageInfo.Name ".ahk")
            PackageInfo.Main := PackageInfo.Name ".ahk"
        else if DirExist(TempDir "\" FinalDirName "\Lib") && FileExist(TempDir "\" FinalDirName "\Lib\" PackageInfo.Name ".ahk")
            PackageInfo.Main := "Lib\" PackageInfo.Name ".ahk"
        else {
            Loop Files TempDir "\" FinalDirName "\*.ahk", "R" {
                if PackageInfo.Main
                    throw Error("Unable to lock onto a specific main file", -1)
                PackageInfo.Main := A_LoopFileName
                if PackageInfo.RepositoryType = "archive"
                    break
            }
        }
    }

    if !IsMainPackage {
        PackageInfo.Main := Trim(StrReplace(PackageInfo.Main, "/", "\"), "\/")
        Includes.Push(PackageInfo)
    } 

    if DirExist(TempDir "\" FinalDirName) && FileExist(TempDir "\" FinalDirName "\package.json") {
        if IsMainPackage {
            LibDir := FindLibDir(TempDir "\" FinalDirName)
            TempDir .= "\" FinalDirName "\" LibDir
        }

        PackageJson := LoadJson(TempDir "\" FinalDirName "\package.json")
        if PackageJson.Has("dependencies") {
            for DependencyName, DependencyVersion in PackageJson["dependencies"]
                DownloadPackageWithDependencies(DependencyName "@" DependencyVersion, TempDir, &Includes)
        }
    }

    return PackageInfo
}

VerifyPackageIsDownloadable(PackageInfo) {
    if IsVersionSha(PackageInfo.Version) {
        if PackageInfo.RepositoryType != "github"
            throw ValueError("In case of SHA version the source address must parse to a GitHub repo")

        if !(PackageInfo.Main && PackageInfo.Files.Length) {
            Repo := StrSplit(PackageInfo.Repository, "/")
            PackageInfo.ZipName := PackageInfo.Version ".zip"
            PackageInfo.SourceAddress := "https://github.com/" Repo[1] "/" Repo[2] "/archive/" PackageInfo.Version ".zip"
        }
    } else if PackageInfo.RepositoryType = "github" {
        if !PackageInfo.Repository
            throw Error("No GitHub repository found in index.json", -1)

        if !(releases := QueryGitHubReleases(PackageInfo.Repository)) || !(releases is Array) || !releases.Length {
            ; No releases found. Try to get commit hash instead.
            if (commits := QueryGitHubCommits(PackageInfo.Repository)) && commits is Array && commits.Length
                PackageInfo.Version := SubStr(commits[1]["sha"], 1, 7)
            else
                throw Error("Unable to find releases or commits for the specified GitHub repository", -1, PackageInfo.PackageName)

            WriteStdOut("No GitHub releases found, installing from default branch")
            if PackageInfo.Main && PackageInfo.Files.Length
                return

            Repo := StrSplit(PackageInfo.Repository, "/")
            PackageInfo.ZipName := (repo.Length = 3 ? repo[3] : QueryGitHubRepo(PackageInfo.Repository)["default_branch"]) ".zip"
            PackageInfo.SourceAddress := "https://github.com/" Repo[1] "/" Repo[2] "/archive/refs/heads/" PackageInfo.ZipName
        } else {
            if !(release := FindMatchingGithubReleaseVersion(releases, PackageInfo.Version))
                throw Error("No matching version found among GitHub releases")

            PackageInfo.Version := release["tag_name"]
            PackageInfo.ZipName := "github_package.zip"
            PackageInfo.SourceAddress := release["zipball_url"]
        }
    } else if PackageInfo.RepositoryType = "archive" {
        PackageInfo.ZipName := "archive_package" (RegExMatch(PackageInfo.Repository, "\.tar\.gz$") ? ".tar.gz" : "." StrSplit(PackageInfo.Repository, ".")[-1])
        PackageInfo.SourceAddress := PackageInfo.Repository
    } else if PackageInfo.RepositoryType = "gist" {
        if !(PackageInfo.Gist := QueryGitHubGist(PackageInfo.Repository)) || !(PackageInfo.Gist is Map) || !PackageInfo.Gist.Has("files")
            throw Error("Unable to find specified gist", -1, PackageInfo.Repository)

        if !PackageInfo.Version || PackageInfo.Version = "latest" || PackageInfo.Version = "*" {
            PackageInfo.Version := SubStr(PackageInfo.Gist["history"][1]["version"], 1, 7), PackageInfo.FullVersion := PackageInfo.Gist["history"][1]["version"]
        } else {
            for Info in PackageInfo.Gist["history"] {
                if SubStr(Info["version"], 1, StrLen(PackageInfo.Version)) = PackageInfo.Version {
                    PackageInfo.Version := SubStr(Info["version"], 1, 7), PackageInfo.FullVersion := Info["version"]
                    return
                }
            }
            throw Error("No matching gist version found", -1, PackageInfo.Version)
        }
    } else if PackageInfo.RepositoryType != "archive" && PackageInfo != "gist"
        throw ValueError("Unknown package source", -1, PackageInfo.RepositoryType)
}

IsPackageInstalled(PackageInfo, Includes, Dirs) {
    for Include in Includes {
        if (Include.PackageName = PackageInfo.PackageName) {
            for Dir in Dirs
                if DirExist(Dir "\" Include.InstallName)
                    return true
        }
    }
    return false
}

DownloadSinglePackage(PackageInfo, TempDir) {
    global g_LastInstalledDependency
    static TempDownloadDir := "~downloaded_package"

    try DirDelete(TempDir "\" TempDownloadDir, 1)

    if PackageInfo.RepositoryType = "github" && IsVersionSha(PackageInfo.Version) && PackageInfo.Main && PackageInfo.Files.Length {
        DirCreate(TempDir "\" TempDownloadDir)
        GithubDownloadMinimalInstall(PackageInfo, TempDir "\" TempDownloadDir)
        goto AfterDownload
    } else if PackageInfo.RepositoryType = "github" {
        ; If the package has only one dependency and the source of that dependency
        if (PackageInfo.Dependencies.Count = 1 && g_LastInstalledDependency.Repository = PackageInfo.Repository) {
            FinalDirName := g_LastInstalledDependency.InstallName
            PackageInfo.InstallName := g_LastInstalledDependency.InstallName, g_LastInstalledDependency := PackageInfo
            return FinalDirName
        }

        if !PackageInfo.HasProp("SourceAddress") && PackageInfo.Main && PackageInfo.Files.Length {
            DirCreate(TempDir "\" TempDownloadDir)
            GithubDownloadMinimalInstall(PackageInfo, TempDir "\" TempDownloadDir)
            goto AfterDownload
        }
    } else if PackageInfo.RepositoryType = "gist" {
        gist := PackageInfo.Gist
        DirCreate(TempDir "\" TempDownloadDir)

        if !PackageInfo.Author
            PackageInfo.Author := gist["owner"]["login"]
        if PackageInfo.Name {
            NameFound := false
            for Name, Info in gist["files"]
                if Name = PackageInfo.Name {
                    NameFound := true
                    PackageInfo.Main := PackageInfo.Name := Info["filename"]
                    if !PackageInfo.Version || PackageInfo.Version = "latest" || PackageInfo.Version = "*" {
                        FileAppend(Info["content"], TempDir "\" TempDownloadDir "\" PackageInfo.Name)
                        goto AfterDownload
                    }
                    break
                }
            if !NameFound
                throw Error("No matching file found in gist", -1, PackageInfo.Name)
        } else {
            for Name, Info in gist["files"] {
                PackageInfo.Main := PackageInfo.Name := Info["filename"]
                break
            }
        }
        PackageInfo.SourceAddress := "https://gist.github.com/raw/" PackageInfo.Repository "/" PackageInfo.FullVersion "/" PackageInfo.Name
        PackageInfo.PackageName := PackageInfo.Author "/" RegExReplace(PackageInfo.Name, "\.ahk\d?$")
        WriteStdOut('Downloading gist as package "' PackageInfo.PackageName '@' PackageInfo.Version '"')
        Download PackageInfo.SourceAddress, TempDir "\" TempDownloadDir "\" PackageInfo.Name
        goto AfterDownload
    }

    WriteStdOut('Downloading package "' PackageInfo.PackageName '"')
    ZipName := PackageInfo.ZipName
    Download PackageInfo.SourceAddress, TempDir "\" ZipName

    if PackageInfo.RepositoryType = "archive"
        PackageInfo.Version := SubStr(HashFile(TempDir "\" ZipName, 3), 1, 7)

    DirCopy TempDir "\" ZipName, TempDir "\" TempDownloadDir, true
    FileDelete(TempDir "\" ZipName)

    Loop Files TempDir "\" TempDownloadDir "\*.*", "D" {
        if PackageInfo.RepositoryType = "archive"
            PackageInfo.Name := A_LoopFileName, PackageInfo.Author := "Archive", PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name
        DirMove(A_LoopFileFullPath, TempDir "\" TempDownloadDir, 2)
        break
    }

    if FileExist(TempDir "\" TempDownloadDir "\package.json") {
        PackageJson := LoadPackageJson(TempDir "\" TempDownloadDir)
        if PackageJson.Has("name") {
            PackageInfo.PackageName := PackageJson["name"]
            Split := ParsePackageName(PackageInfo.PackageName)
            PackageInfo.Name := Split.Name, PackageInfo.Author := Split.Author
        }
        if PackageJson.Has("version")
            PackageInfo.Version := PackageJson["version"]
    }

    AfterDownload:

    FinalDirName := PackageInfo.Author "_" RegExReplace(PackageInfo.Name, "\.ahk\d?$") "_" PackageInfo.Version
    PackageInfo.InstallName := FinalDirName
    g_LastInstalledDependency := PackageInfo

    if DirExist(TempDir "\" FinalDirName) || DirExist("Lib\" FinalDirName) {
        WriteStdOut 'Package "' FinalDirName '" already installed or up-to-date, skipping...'
        DirDelete(TempDir "\" TempDownloadDir, true)
        return 0
    }

    DirMove(TempDir "\" TempDownloadDir, TempDir "\" FinalDirName)
    return FinalDirName
}

GithubDownloadMinimalInstall(PackageInfo, Path) {
    WriteStdOut('Downloading minimal install for package "' PackageInfo.PackageName '"')

    Path := Trim(Path, "\/")
    Repo := StrSplit(PackageInfo.Repository, "/")
    if PackageInfo.Files.Length = 1 {
        Result := QueryGitHubRepo(PackageInfo.Repository, "commits?path=" PackageInfo.Files[1])
        PackageInfo.Version := SubStr(Result[1]["sha"], 1, 7)
        PackageInfo.MainPath := PackageInfo.Main, PackageInfo.Main := StrSplit(PackageInfo.Main, "/")[-1]
        Download("https://github.com/" Repo[1] "/" Repo[2] "/raw/" PackageInfo.Version "/"  PackageInfo.MainPath, Path "\" PackageInfo.Main)
        Download("https://github.com/" Repo[1] "/" Repo[2] "/raw/" PackageInfo.Version "/LICENSE", Path "\LICENSE")
        if InStr(FileRead(Path "\LICENSE"), "<!DOCTYPE html>")
            FileDelete(Path "\LICENSE")
        return
    }

    for MinFile in PackageInfo.Files {
        MinFile := StrReplace(MinFile, "/", "\")
        TargetPath := ""
        Split := StrSplit(MinFile, "\")
        if Split.Length > 1 {
            Dirs := Split.Clone(), Dirs.Pop()
            for Dir in Dirs {
                TargetPath .= "\" Dir
                if !DirExist(Path TargetPath)
                    DirCreate(Path TargetPath)
            }
        }
        Download("https://github.com/" Repo[1] "/" Repo[2] "/raw/" PackageInfo.Version "/" MinFile, Path TargetPath "\" Split[-1])
    }   
}

ForceRemovePackage(PackageInfo, LibDir) {
    DirDelete(".\" LibDir "\" PackageInfo.InstallName, true)
    if FileExist(".\" LibDir "\packages.ahk") {
        OldPackages := FileRead(".\" LibDir "\packages.ahk")
        NewPackages := RegExReplace(OldPackages, ".*\Q\" PackageInfo.InstallName "\\E.*\n\r?",,, 1)
        if OldPackages != NewPackages
            FileOpen(".\" LibDir "\packages.ahk", "w").Write(NewPackages)
    }
    if FileExist(".\package.json") {
        PackageJson := LoadPackageJson(A_WorkingDir, &OldContent:="")
        if PackageJson["dependencies"].Has(PackageInfo.PackageName) {
            PackageJson["dependencies"].Delete(PackageInfo.PackageName)
            NewContent := JSON.Dump(PackageJson, true)
            if OldContent != NewContent && NewContent
                FileOpen(".\package.json", "w").Write(NewContent)
        }
    }
}

ForceRemovePackageWithDependencies(PackageInfo, InstalledPackages, LibDir) {
    ForceRemovePackage(PackageInfo, LibDir)
    Dependencies := QueryInstalledPackageDependencies(PackageInfo, InstalledPackages, LibDir)
    for Dependency, Version in Dependencies {
        DependencyInfo := ExtractPackageInfoFromNameAndIndex(Dependency "@" Version)
        ForceRemovePackage(DependencyInfo, LibDir)
        for i, InstalledPackage in InstalledPackages {
            if (InstalledPackage.PackageName = DependencyInfo.PackageName && InstalledPackage.Version = DependencyInfo.Version) {
                InstalledPackage.RemoveAt(i)
                break
            }
        }
        ForceRemovePackageWithDependencies(DependencyInfo, InstalledPackages, LibDir)
    }
}

RemovePackage(PackageName) {
    PackageInfo := ParsePackageName(PackageName)
    InstalledPackages := ParseInstalledPackages()

    if !(Matches := FindMatchingInstalledPackages(PackageInfo, InstalledPackages))
        return

    if !Matches.Length {
        WriteStdOut "No such package installed"
    } else if Matches.Length = 1 {
        Match := Matches[1]
        LibDir := FindLibDir()

        Dependencies := QueryInstalledPackageDependencies(Match, InstalledPackages, LibDir)
        if Dependencies.Length {
            DepString := 'Cannot remove package "' Match.PackageName "@" Match.Version '" as it is depended on by: '
            for Dependency in Dependencies
                DepString .= "`n`t" Dependency.PackageName "@" Dependency.Version

            WriteStdOut DepString
            return
        }

        ForceRemovePackage(Match, LibDir)
        WriteStdOut 'Package "' Match.PackageName "@" Match.Version '" removed!'
    } else {
        WriteStdOut "Multiple matches found:"
        for Match in Matches
            WriteStdOut "`t" Match.PackageName "@" Match.Version
    }
}

FindMatchingInstalledPackages(PackageInfo, InstalledPackages) {
    if !FileExist("package.json")
        return WriteStdOut("No package.json found")

    ; Validate that the removed package is a dependency of the project
    PackageJson := LoadPackageJson(A_WorkingDir)
    if !(PackageJson.Has("dependencies") && PackageJson["dependencies"].Count)
        return WriteStdOut("No dependencies found in package.json, cannot remove package")

    Matches := []
    for Package in InstalledPackages {
        if Package.Name != PackageInfo.Name
            continue
        if Package.Author && PackageInfo.Author && Package.Author != PackageInfo.Author
            continue
        Matches.Push(Package)
    }
    if Matches.Length > 1 {
        Backup := Matches, Matches := []
        for Match in Backup {
            if !VerCompare(Match.Version, PackageInfo.Version)
                Matches.Push(Match)
        }
    }
    return Matches
}

QueryInstalledPackageDependencies(PackageInfo, InstalledPackages, LibDir) {
    DependencyList := []
    for InstalledPackage in InstalledPackages {
        if InstalledPackage.InstallName = PackageInfo.InstallName
            continue
        PackageDir := A_WorkingDir "\" LibDir "\" InstalledPackage.InstallName
        Dependencies := Map()
        if FileExist(PackageDir "\package.json") {
            PackageJson := LoadPackageJson(PackageDir)
            if PackageJson.Has("dependencies")
                Dependencies := PackageJson["dependencies"]
        } else {
            if g_Index.Has(InstalledPackage.PackageName) && g_Index[InstalledPackage.PackageName].Has("dependencies")
                Dependencies := g_Index[InstalledPackage.PackageName]["dependencies"]
        }

        for DependencyName, DependencyVersion in Dependencies {
            if DependencyName = PackageInfo.PackageName && IsVersionCompatible(PackageInfo.Version, DependencyVersion)
                DependencyList.Push(InstalledPackage)
        }
    }

    return DependencyList
}

LoadPackageIndex() {
    if !FileExist(A_ScriptDir "\assets\index.json")
        DownloadPackageIndex()
    global g_Index := LoadJson(A_ScriptDir "\assets\index.json")
    for PackageName, Info in g_Index {
        if !IsObject(Info)
            continue
        if !Info.Has("author")
            Info["author"] := StrSplit(PackageName, "/")[1]
        if !Info.Has("repository")
            Info["repository"] := Map("type", "github", "url", PackageName)
        else
            StandardizeRepositoryInfo(Info)
        if (!Info.Has("main") || Info["main"] = "") && Info.Has("files") && Info["files"].Length = 1 && Info["files"][1] ~= "\.ahk\d?$"
            Info["main"] := Info["files"][1]
        if !Info.Has("main")
            Info["main"] := ""
    }
}

LoadConfig() {
    global g_Config
    if !FileExist(A_ScriptDir "\assets\config.json")
        g_Config := Map()
    else
        g_Config := LoadJson(A_ScriptDir "\assets\config.json")
}

DownloadPackageIndex() {
    ; Download(g_GitHubRawBase "assets\index.json", A_ScriptDir "\assets\index.json")
}

UpdatePackageIndex() {
    DownloadPackageIndex()
    LoadPackageIndex()
}

ListInstalledPackages() {
    Packages := ParseInstalledPackages()
    for Package in Packages
        WriteStdOut Package.PackageName "@" Package.Version
}

ParseInstalledPackages() {
    LibDir := FindLibDir()
    if !FileExist(".\" LibDir "\packages.ahk")
        return []

    Packages := []

    Loop parse FileRead(".\" LibDir "\packages.ahk"), "`n", "`r" {
        if !(A_LoopField ~= "^\s*#include")
            continue

        Split := StrSplit(A_LoopField, "\")
        for Part in Split {
            try {
                Packages.Push(ExtractPackageInfoFromInstallName(Part))
                break
            }
        }
    }

    return Packages
}

FindLibDir(path := ".\") {
    path := RTrim(path, "\") "\"
    if DirExist(path "lib")
        return "lib"
    else if DirExist(path "includes")
        return "includes"
    return "lib"
}

FindMatchingGithubReleaseVersion(releases, target) {
    CompareFunc := GetVersionRangeCompareFunc(target)

    last := "0", latest := ""
    for release in releases {
        ver := release["tag_name"]
        if CompareFunc(ver) && VerCompare(ver, ">=" last)
            last := ver, latest := release
    }
    return latest
}

FindMatchingGistVersion(gist_file, target) {
    CompareFunc := GetVersionRangeCompareFunc(target)

    last := "0", latest := ""
    for gist_info in gist_file {
        ver := gist_info["tag_name"]
        if CompareFunc(ver) && VerCompare(ver, ">=" last)
            last := ver, latest := gist_info
    }
    return latest
}

GetVersionRangeCompareFunc(range) {
    range := StrLower(range)
    if range = "*"
        range := "latest"
    if range != "latest" {
        plain := RegExReplace(range, "[^\w-.]")
        if SubStr(plain, 1, 1) = "v"
            plain := SubStr(plain, 2)
        if IsVersionSha(plain)
            return (v) => v == plain
        split := StrSplit(plain, ".")
        if split.Length = 3 && split[3] = "x"
            split[3] := "0", range := "~" range, plain := StrReplace(plain, ".x", ".0")
        if split.Length = 2 && split[2] = "x"
            split[2] := "0", range := "^" range, plain := StrReplace(plain, ".x", ".0")
        switch SubStr(range, 1, 1) {
            case "~": ; Only accept patch versions
                CompareFunc := (v) => VerCompare(v, ">=" plain) && VerCompare(v, (split.Length > 1) ? "<" split[1] "." (Integer(split[2])+1) : "=" split[1])
            case "^": ; Only accept minor and patch versions
                CompareFunc := (v) => VerCompare(v, ">=" plain) && VerCompare(v, "<" (Integer(split[1])+1))
            case ">", "<":
                CompareFunc := VerCompare.Bind(, range)
            default:
                CompareFunc := (v) => VerCompare(v, "=" plain)
        }
    } else
        CompareFunc := (v) => true
    return CompareFunc
}

IsVersionSha(version) => StrLen(version) = 7 && RegExMatch(version, "^\w+$")

IsVersionCompatible(version, range) => GetVersionRangeCompareFunc(range).Call(version)

FindMatchingPackage(PackageInfo) {
    if PackageInfo.Author = "" {
        found := []
        for Name, Info in g_Index {
            if Name ~= "i)\/\Q" PackageInfo.Name "\E$"
                found.Push(Name)
        }
        if !found.Length
            throw Error("No matching package found in index", -1, PackageInfo.Name)
        Temp := ParsePackageName(found[1] "@" PackageInfo.Version)
        PackageInfo.Name := Temp.Name, PackageInfo.Author := Temp.Author, PackageInfo.PackageName := Temp.PackageName
        MergeIndexInfoToPackageInfo(g_Index[found[1]], PackageInfo)
        return found.Length > 1 ? found : PackageInfo
    }
    
    if g_Index.Has(PackageInfo.PackageName) {
        MergeIndexInfoToPackageInfo(g_Index[PackageInfo.PackageName], PackageInfo)
        return PackageInfo
    } else {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", "https://api.github.com/repos/" PackageInfo.Author "/" PackageInfo.Name, true)
        whr.SetRequestHeader("Accept", "application/vnd.github+json")
        whr.Send()
        whr.WaitForResponse()
        res := whr.ResponseText
        if InStr(whr.ResponseText, '"name"') {
            MergeIndexInfoToPackageInfo(Map("repository", Map("type", "github", "url", PackageInfo.Author "/" PackageInfo.Name), "author", PackageInfo.Author), PackageInfo)
            return PackageInfo
        }
        throw ValueError("Package not found", -1, PackageInfo.Name)
    }
        
}

MergeIndexInfoToPackageInfo(IndexInfo, PackageInfo) {
    if !PackageInfo.HasProp("dependencies") || !PackageInfo.Dependencies || !PackageInfo.Dependencies.Count
        PackageInfo.Dependencies := IndexInfo.Has("dependencies") ? IndexInfo["dependencies"] : Map()
    if !PackageInfo.HasProp("repository") || !PackageInfo.Repository
        PackageInfo.Repository := IndexInfo["repository"]["url"], PackageInfo.RepositoryType := IndexInfo["repository"]["type"]
    if !PackageInfo.HasProp("Files") || !PackageInfo.Files.Length
        PackageInfo.Files := IndexInfo.Has("files") ? IndexInfo["files"] : []
    if !PackageInfo.HasProp("main") || !PackageInfo.Main
        PackageInfo.Main := IndexInfo.Has("main") ? IndexInfo["main"] : ""
    return PackageInfo
}

ParsePackageName(PackageName) {
    PackageInfo := {Author:"", Name:"", Version:"", PackageName:""}
    SplitId := StrSplit(PackageName, "@")
    if SplitId.Length > 1 {
        PackageInfo.Version := SplitId.Pop()
        PackageName := ""
        for part in SplitId
            PackageName .= part "@"
        PackageName := SubStr(PackageName, 1, -1)
    } else
        PackageInfo.Version := "latest"

    SplitId := StrSplit(PackageName, "/",, 2)
    switch SplitId.Length {
        case 1: ; Just "Package"
            PackageInfo.Name := SplitId[1], PackageInfo.Author := ""
        case 2: ; "Author/Package"
            PackageInfo.Author := SplitId[1], PackageInfo.Name := SplitId[2]
        default:
            throw ValueError("Invalid package name", -1, PackageName)
    }
    PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name
    return PackageInfo
}

ExtractPackageInfoFromNameAndIndex(source) {
    PackageInfo := {Author:"", Name:"", PackageName:"", Version:"", Repository:"", RepositoryType:"github", Main:"", Dependencies:Map(), Files:[]}
    StrReplace(source, "/", "",, &SlashCount:=0)

    if source ~= "^(github|gh):"
        source := StrSplit(source, ":",,2)[2]

    if source ~= "^gist:" {
        PackageInfo.Repository := StrSplit(source, ":",,2)[2]
        if InStr(PackageInfo.Repository, "/") {
            PackageInfo.Repository := StrSplit(PackageInfo.Repository, "/")
            PackageInfo.Name := PackageInfo.Repository[2]
            PackageInfo.Repository := PackageInfo.Repository[1]
        }
        PackageInfo.RepositoryType := "gist"
    } else if SlashCount < 2 { ; Package name queried from index
        ParsedName := ParsePackageName(source)
        PackageInfo.Author := ParsedName.Author, PackageInfo.Name := ParsedName.Name, PackageInfo.PackageName := ParsedName.PackageName, PackageInfo.Version := ParsedName.Version
        if PackageInfo.Name
            PackageInfo := FindMatchingPackage(PackageInfo)
    
        if PackageInfo is Array
            throw Error("Multiple matches found")
    } else {
        RepoInfo := ExtractRepositoryInfo(source)
        PackageInfo.Repository := RepoInfo["url"]
        PackageInfo.RepositoryType := RepoInfo["type"]
        SplitSource := StrSplit(PackageInfo.Repository, "/",, 2)
        
        if PackageInfo.RepositoryType = "github"
            PackageInfo.Author := SplitSource[1], PackageInfo.Name := SplitSource[2], PackageInfo.PackageName := PackageInfo.Repository
        else if PackageInfo.RepositoryType = "archive"
            PackageInfo.Name := SplitSource[-1], SplitPath(PackageInfo.Name,,,, &NameNoExt:=""), PackageInfo.PackageName := NameNoExt
    }

    if !PackageInfo.Repository && PackageInfo.RepositoryType = "github"
        PackageInfo.Repository := PackageInfo.PackageName
    return PackageInfo
}

ExtractPackageInfoFromInstallName(InstallName) {
    PackageInfo := {Author:"", Name:"", Version:"", PackageName:"", InstallName:InstallName}
    StrReplace(InstallName, "_",,, &Count:=0)
    if Count < 2
        throw Error("Invalid package install name", -1, InstallName)

    SubSplit := StrSplit(InstallName, "_",, 2)
    PackageInfo.Author := SubSplit[1]
    PackageInfo.Name := SubStr(SubSplit[2], 1, InStr(SubSplit[2], "_",,-1)-1)
    PackageInfo.Version := SubStr(SubSplit[2], InStr(SubSplit[2], "_",,-1)+1)
    PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name
    return PackageInfo        
}

QueryGitHubGist(GistId, subrequest := "", data := "") {
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    GistId := Trim(GistId, "\/")
    if (subrequest := Trim(subrequest, "/\"))
        subrequest := "/" subrequest

    whr.Open("GET", "https://api.github.com/gists/" GistId subrequest (data ? ObjToQuery(data) : ""), true)
    whr.SetRequestHeader("Accept", "application/vnd.github+json")
    if g_Config.Has("github_token")
        whr.SetRequestHeader("Authorization", "Bearer " g_Config["github_token"])
    whr.Send()
    whr.WaitForResponse()
    return JSON.Load(whr.ResponseText)
}

QueryGitHubRepo(repo, subrequest := "", data := "", token := "") {
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    repo := StrSplit(repo, "/")
    if (subrequest := Trim(subrequest, "/\"))
        subrequest := "/" subrequest

    whr.Open("GET", "https://api.github.com/repos/" repo[1] "/" repo[2] subrequest (data ? ObjToQuery(data) : ""), true)
    whr.SetRequestHeader("Accept", "application/vnd.github+json")
    if g_Config.Has("github_token")
        whr.SetRequestHeader("Authorization", "Bearer " g_Config["github_token"])
    whr.Send()
    whr.WaitForResponse()
    return JSON.Load(whr.ResponseText)
}

QueryGitHubReleases(repo) => QueryGitHubRepo(repo, "releases")
QueryGitHubCommits(repo) => QueryGitHubRepo(repo, "commits")

LoadPackageJson(path:=".\", &RawContent:="") {
    PackageJson := LoadJson(RTrim(path, "\") "\package.json", &RawContent)
    PackageJson.Default := ""
    StandardizeRepositoryInfo(PackageJson)
    return PackageJson
}
LoadJson(fileName, &RawContent:="") => RawContent := JSON.Load(FileRead(fileName))

StandardizeRepositoryInfo(Info) {
    if !Info.Has("repository")
        return
    if IsObject(Info["repository"]) {
        if !Info["repository"].Has("type") && Info["repository"].Has("url")
            Info["repository"] := Info["repository"]["url"]
        else
            return
    }
    Info["repository"] := ExtractRepositoryInfo(Info["repository"])
}

ExtractRepositoryInfo(repo) {
    repo := Trim(repo, "/\")
    if !repo
        return Map("type", "github", "url", "")
    if repo ~= "(\.zip|\.tar\.gz|\.tar|\.7z)$"
        repo := Map("type", "archive", "url", repo)
    else if InStr(repo, "github.com")
        repo := Map("type", "github", "url", RegExReplace(repo, ".*github\.com\/"))
    else if repo ~= "^(http|ftp)"
        repo := Map("type", "archive", "url", repo)
    else if repo ~= "^(github:|gh:)"
        repo := Map("type", "github", "url", StrSplit(repo, ":",,2)[2])
    else if repo ~= "^(gist:)"
        repo := Map("type", "gist", "url", StrSplit(repo, ":",,2)[2])
    else
        repo := Map("type", "github", "url", repo)
    return repo
}

WriteStdOut(msg) => FileAppend(msg "`n", "*")