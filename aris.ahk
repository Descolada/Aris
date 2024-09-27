/*
    ARIS: AutoHotkey Repository Install System

    Requirements that Aris must fulfill and situations it must handle:
    1) Installing a library should install it either in Lib or includes folder (hereby mentioned as the Lib folder), whichever exists.
    2) Installation creates a packages.ahk file, which also acts as a lock file describing the exact dependencies needed.
    3) Installation creates a package.json file to describe the range of dependencies allowed. This should
        be done automatically without needing user input, as most users simply want to use a library, not enter info
        about their own project.
    4) If an installed library has package.json, then its dependencies should also be installed in the main Lib folder
    5) A package is considered "installed" if it has an entry in package.json dependencies, packages.ahk #include,
        and it has an install folder in Lib folder
    6) "aris install" should query for package.json, packages.ahk, and search all .ahk files for matching
        ARIS version style "Author_Name_Version".
    7) Dependencies should also be findable if a package.json and packages.ahk don't exist. In that case
        all .ahk files should be queried for matching ARIS version styles AND that entry must contain
        all pertinent information for installing the package.
        This is especially important with archive installs or Gists, as the ARIS version will contain
        only a hash, which means the source will need to be added as a comment after it. The source is 
        optional for GitHub installs.
    8) Supported install locations/commands:
        aris i Name          => queries index.json for a matching package, and if only 1 match is found then it's installed
        aris i Author/Name   => queries index.json, otherwise falls back to GitHub main branch
        aris i Name@version  => Requires a specific version range. If a specific version is specified then other installed versions are automatically removed.
        aris i Name@ShortHash    => Requires a specific GitHub commit
        aris i Author/Name/branch    => installs a GitHub branch
        aris i github:URL    => installs from a GitHub link. URL can also be in the short form Author/Name
        aris i gist:hash         => installs the first found file in a Gist
        aris i gist:hash/file    => installs a specific file from a Gist
        aris i forums:t=thread-id  => Installs from a AHK forums thread, the first encountered code-box
        aris i forums:t=thread-id&codebox=number  => Installs from a AHK forums thread, optionally a codebox number can be specified
        aris i URL           => GitHub URL, or AHK forums URL, or an archive (.zip, .tar.bz) link
*/

; Raw files:
; https://github.com/user/repository/raw/branch/filename
; https://github.com/user/repository/raw/{commitID}/filename
; https://github.com/{user}/{repo}/raw/{branch}/{path}
; https://raw.github.com/{user}/{repo}/raw/{branch}/{path}?token={token}


; Specific commit links:
; https://github.com/{user}/{repo}/blob/{commitID}/{filename}
; https://github.com/{user}/{repo}/raw/{commitID}/{filename}

; Branch links:
; https://github.com/{user}/{repo}/blob/v2/Dist/{filename}
; https://github.com/{user}/{repo}/archive/refs/heads/{branch}.{tar.gz|.zip}

; Release links:
; https://github.com/{user}/{repo}/releases/tag/{releasetag}/{filename}
; https://github.com/{user}/{repo}/releases/download/{releasetag}/{releasename}


; Gist links:
; https://gist.github.com/raw/[ID]/[REVISION]/[FILE]

#Requires AutoHotkey v2

TraySetIcon A_ScriptDir "\assets\main.ico"

;#include <packages>
#include <cJSON>
#include <ui-main>
#include <utils>

global g_GitHubRawBase := "https://raw.githubusercontent.com/Descolada/ARIS/main/", g_Index, g_Config := Map(), g_PackageJson, g_LibDir, g_InstalledPackages
global g_Switches := Mapi("global_install", false, "force", false, "main", "", "files", []), g_CacheDir := A_ScriptDir "\cache"
global g_CommandAliases := Mapi("install", "install", "i", "install", "remove", "remove", "r", "remove", "rm", "remove", "uninstall", "remove", "update", "update", "update-index", "update-index", "list", "list", "clean", "clean")
global g_SwitchAliases := Mapi("--global-install", "global_install", "-g", "global_install", "-f", "force", "--force", "force", "--main", "main", "-m", "main", "--files", "files")
A_FileEncoding := "UTF-8"

for i, Arg in A_Args {
    if Arg = "--working-dir" {
        if A_Args.Length > i && DirExist(A_Args[i+1]) {
            SetWorkingDir(A_Args[i+1]), A_Args.RemoveAt(i, 2)
            break
        } else
            throw Error("Invalid working directory specified")
    }
}

RefreshGlobals()

Loop files A_ScriptDir "\*.*", "D" {
    if A_LoopFileName ~= "^~temp-\d+"
        DirDelete(A_LoopFileFullPath, true)
}

ClearCache()

if !g_Config.Has("first_run") {
    AddArisToPATH()
    g_Config["first_run"] := false
    FileOpen("assets/config.json", "w").Write(JSON.Dump(g_Config, true))
}


if (!A_Args.Length) {
    Persistent()
    LaunchGui()
} else {
    DllCall("AttachConsole", "UInt", 0x0ffffffff, "ptr")
    Command := "", Targets := [], Files := [], LastSwitch := ""
    for i, Arg in A_Args {
        if LastSwitch = "main" {
            LastSwitch := "", g_Switches["main"] := StrReplace(Arg, "\", "/")
            continue
        }
        if g_CommandAliases.Has(Arg)
            Command := g_CommandAliases[Arg]
        else if g_SwitchAliases.Has(Arg) {
            if g_SwitchAliases[Arg] = "main" || g_SwitchAliases[Arg] = "files" {
                LastSwitch := g_SwitchAliases[Arg]
                continue
            }
            g_Switches[g_SwitchAliases[Arg]] := true
        } else if !Command && !LastSwitch
            WriteStdOut("Unknown command. Use install, remove, update, or list."), ExitApp()
        else {
            if LastSwitch = "files" {
                g_Switches["files"].Push(StrReplace(Arg, "\", "/"))
                continue
            }
            Targets.Push(Arg)
        }
        LastSwitch := ""
    }
    switch Command, 0 {
        case "install":
            if Targets.Length {
                for target in Targets
                    InstallPackage(target)
            } else {
                InstallPackageDependencies()
            }
        case "remove":
            if Targets.Length {
                for target in Targets
                    RemovePackage(target)
            } else
                WriteStdOut("Specify a package to remove.")
        case "update":
            if !FileExist(A_WorkingDir "\package.json")
                throw ValueError("Missing package.json, cannot update package", -1)
            if Targets.Length {
                for target in Targets
                    InstallPackage(target, 1)
            } else {
                ThisPackage := ParsePackageName(g_PackageJson["name"])
                MergeJsonInfoToPackageInfo(g_PackageJson, ThisPackage)
                ThisPackage.IsMain := 1
                ThisPackage.Files := ["*.*"]
                InstallPackage(ThisPackage, 1)
            }
        case "update-index":
            UpdatePackageIndex()
        case "list":
            ListInstalledPackages()
        case "clean":
            CleanPackages()
            ClearCache(true)
    }
}

ClearCache(Force := false) {
    if Force || (g_Config.Has("last_cache_clear") && g_Config["last_cache_clear"] && DateDiff(A_Now, g_Config["last_cache_clear"], "Days") > 30) {
        if DirExist(g_CacheDir)
            DirDelete(g_CacheDir, true)
        DirCreate(g_CacheDir)
        g_Config["last_cache_clear"] := A_Now
        SaveSettings()
    }
}

AddArisToPATH() {
    ; Get the current PATH in this roundabout way because of the Store version registry virtualization
    CurrPath := RunCMD(A_ComSpec . " /c " 'reg query HKCU\Environment /v PATH')
    CurrPath := RegExReplace(CurrPath, "^[\w\W]*?PATH\s+REG_SZ\s+",,,1)
    if !CurrPath
        return
    if !(LocalAppData := EnvGet("LOCALAPPDATA"))
        return
    BatContent := '@echo off`n@"' A_AhkPath '" "' A_ScriptFullPath '" "--working-dir" "%cd%" %*'
    if !DirExist(LocalAppData "\Programs\Aris")
        DirCreate(LocalAppData "\Programs\Aris")
    if !FileExist(LocalAppData "\Programs\Aris\Aris.bat") || FileRead(LocalAppData "\Programs\Aris\Aris.bat") != BatContent
        FileOpen(LocalAppData "\Programs\Aris\Aris.bat", "w", "CP0").Write(BatContent)
    if !InStr(CurrPath, LocalAppData "\Programs\Aris") {
        FileOpen(A_ScriptDir "\assets\user-path-backup.txt", "w").Write(CurrPath)
        ; https://stackoverflow.com/questions/9546324/adding-a-directory-to-the-path-environment-variable-in-windows
        RunWait A_ComSpec ' /c SETX PATH "' CurrPath '";"' LocalAppData '\Programs\Aris"',, "Hide"
        SendMessage(0x1A, 0, StrPtr("Environment"), 0xFFFF)
    }
}

RemoveArisFromPATH() {
    if !(LocalAppData := EnvGet("LOCALAPPDATA"))
        return

    CurrPath := RunCMD(A_ComSpec . " /c " 'reg query HKCU\Environment /v PATH')
    CurrPath := RegExReplace(CurrPath, "^[\w\W]*?PATH\s+REG_SZ\s+",,,1)

    if CurrPath && InStr(CurrPath, ";" LocalAppData "\Programs\Aris") {
        RunWait A_ComSpec ' /c SETX PATH "' StrReplace(CurrPath, ";" LocalAppData "\Programs\Aris") '"',, "Hide"
        SendMessage(0x1A, 0, StrPtr("Environment"), 0xFFFF)
    }
    if FileExist(LocalAppData "\Programs\Aris\Aris.bat") {
        DirDelete(LocalAppData "\Programs\Aris", true)
    }
}

IsArisInPATH() {
    if !(LocalAppData := EnvGet("LOCALAPPDATA"))
        return false
    CurrPath := RunCMD(A_ComSpec . " /c " 'reg query HKCU\Environment /v PATH')
    CurrPath := RegExReplace(CurrPath, "^[\w\W]*?PATH\s+REG_SZ\s+",,,1)
    if CurrPath && InStr(CurrPath, LocalAppData "\Programs\Aris")
        return true
    return false
}

RefreshGlobals() {
    LoadPackageIndex()
    LoadConfig()
    RefreshWorkingDirGlobals()
}

RefreshWorkingDirGlobals() {
    global g_PackageJson := LoadPackageJson()
    global g_LibDir := FindLibDir()
    global g_InstalledPackages := QueryInstalledPackages()
}

InstallPackageDependencies() {
    Dependencies := QueryPackageDependencies()
    if !Dependencies.Count {
        WriteStdOut "No dependencies found"
        return
    }
    for PackageName, PackageInfo in Dependencies
        InstallPackage(PackageInfo, 2) ; InStr(PackageInfo.DependencyEntry, ":") ? PackageInfo.DependencyEntry : PackageName "@" PackageInfo.Version)
}

UpdatePackage(PackageName) {
    PackageInfo := ParsePackageName(PackageName)

    if !(Matches := FindMatchingInstalledPackages(PackageInfo, g_InstalledPackages))
        return

    if !Matches.Length
        return WriteStdOut("No matching installed packages found: `"" PackageName "`"")

    if Matches.Length > 1 {
        WriteStdOut "Multiple matches found:"
        for Match in Matches
            WriteStdOut "`t" Match.PackageName "@" Match.InstallVersion
    } else {
        try {
            if InstallPackage(Matches[1].PackageName "@" g_PackageJson[Matches[1].PackageName], 1)
                WriteStdOut "Package successfully updated!"
        }
    }
}

/*
    Minimum info for download:
        Github username + repo
        Gist username + hash
        Archive URL (package info is extracted after download)

    Info required for install:
        Author, Name, Version
            Github: repository
            Forums: thread id, file hash
            Gist: gist hash

        Optional:
            Files (default: [*]), Dependencies (default: none), Main (default: same as repo, or main.ahk, or export.ahk, or the only ahk file)
            PackageName (may be used to generate package folders with different namings if specified in package.json)
                Gist: file name
                Forums: codebox number
*/
class PackageInfoBase {
    __New(Author:="", Name:="", Version:="") {
        this.Author := Author, this.Name := Name, this.Version:=Version
        if Author && Name
            this.PackageName := Author "/" Name
    }
    Author := "", Name := "", PackageName := "", Version := "", Hash := "", Repository := "", 
    RepositoryType := "", Main := "", Dependencies := Map(), DependencyEntry := "", Files := [],
    Branch := "", ThreadId := "", InstallVersion := "", DependencyVersion := "", IsMain := 0
}

InputToPackageInfo(Input) {
    PackageInfo := PackageInfoBase()
    if loc := InStr(Input, "@",,-1) {
        PackageInfo.Version := SubStr(Input, loc+1)
        Input := SubStr(Input, 1, loc-1)
        if loc := InStr(PackageInfo.Version, "+",,-1)
            PackageInfo.Hash := SubStr(PackageInfo.Version, loc+1), PackageInfo.Version := SubStr(PackageInfo.Version, 1, loc-1)
    }
    Input := Trim(Input, "/\")
    
    if !Input
        throw Error("Couldn't find a target package", -1, Input)

    PackageInfo.Repository := Input
    ParseRepositoryData(PackageInfo)

    if PackageInfo.RepositoryType
        return PackageInfo

    FoundPackageInfo := SearchPackageByName(Input)
    FoundPackageInfo.Version := PackageInfo.Version || FoundPackageInfo.Version || PackageInfo.InstallVersion || FoundPackageInfo.InstallVersion, FoundPackageInfo.Hash := PackageInfo.Hash || FoundPackageInfo.Hash
    return FoundPackageInfo
}

ParseRepositoryData(PackageInfo) {
    Input := PackageInfo.Repository
    if !PackageInfo.RepositoryType {
        if Input ~= "(\.zip|\.tar\.gz|\.tar|\.7z)$" {
            PackageInfo.RepositoryType := "archive"
        } else if InStr(Input, "gist.github.com") || Input ~= "^(gist:)" {
            PackageInfo.RepositoryType := "gist"
        } else if InStr(Input, "github.com") || Input ~= "^(github|gh):" {
            PackageInfo.RepositoryType := "github"
        } else if InStr(Input, "autohotkey.com") || Input ~= "^(forums:)" {
            PackageInfo.RepositoryType := "forums"
        } else {
            Split := StrSplit(Input, "/")
            if Split.Length > 3 {
                PackageInfo.RepositoryType := "archive", PackageInfo.Repository := Input
            } else 
                return
        }
    }

    switch PackageInfo.RepositoryType, 0 {
        case "archive":
            SplitSource := StrSplit(PackageInfo.Repository, "/")
            PackageInfo.Name := SplitSource[-1], SplitPath(PackageInfo.Name,,,, &NameNoExt:=""), PackageInfo.PackageName := NameNoExt
        case "github":
            PackageInfo.Repository := StrSplit(RegExReplace(Input, ".*github\.com\/", ":",, 1), ":",, 2)[-1]
            Split := StrSplit(PackageInfo.Repository)
            PackageInfo.Author := PackageInfo.Author || Split[1], PackageInfo.Name := PackageInfo.Name || Split[2], PackageInfo.Branch := Split.Length = 3 ? Split[3] : ""
        case "forums":
            if !RegExMatch(Input, "t=(\d+).*?((?<=code=|codebox=)\d+)?$", &match:="")
                throw Error("Detected AutoHotkey forums link, but couldn't find thread id", -1, Input)
            PackageInfo.ThreadId := match[1], PackageInfo.CodeBox := (match.Count = 2 && match[2] ? Integer(match[2]) : 1)
            PackageInfo.Start := RegExMatch(Input, "&start=(\d+)", &match:="") ? match[1] : ""
            PackageInfo.Post := RegExMatch(Input, "&p=(\d+)", &match:="") ? match[1] : ""
            if PackageInfo.Version = "latest" || PackageInfo.Hash
                PackageInfo.Repository := "https://www.autohotkey.com/boards/viewtopic.php?t=" PackageInfo.ThreadId (PackageInfo.Start ? "&start=" PackageInfo.Start : "") (PackageInfo.Post ? "&p=" PackageInfo.Post : "") "&codenum=" PackageInfo.CodeBox
            if RegExMatch(PackageInfo.Version, "^([><=]*)(\d+)$", &match:="") && (len := StrLen(match[2])) != 14
                PackageInfo.Version := match[1] (Integer(match[2]) * 10**(14-len))
            ; Wayback Machine repo name is generated after finding a version match or latest version
        case "gist":
            PackageInfo.Repository := StrSplit(Input := RegExReplace(Input, ".*github\.com\/[^\/]+/", ":",, 1), ":",,2)[-1]
            if InStr(Input, "/") {
                Split := StrSplit(PackageInfo.Repository, "/")
                PackageInfo.Repository := Split[1]
                PackageInfo.Main := Split[2]
                PackageInfo.Name := PackageInfo.Name || PackageInfo.Main
            }
    }
}

InstallInfoToPackageInfo(InstallInfo) {
    StrReplace(InstallInfo, "_",,, &Count:=0)
    if Count < 2
        throw Error("Invalid package install name", -1, InstallInfo)

    if !RegExMatch(InstallInfo, "([^\\_]+_[^\\_]+_[^\\]+)", &InstallName:="")
        throw Error("Package install name not found", -1, InstallInfo)

    Split := StrSplit(InstallInfo, " `; Source: ")
    if Split.Length = 2 {
        PackageInfo := InputToPackageInfo(Split[2])
        PackageInfo.InstallVersion := PackageInfo.Version, PackageInfo.Version := ""
        PackageInfo.DependencyEntry := Split[2]
    } else
        PackageInfo := PackageInfoBase()

    PackageInfo.Main := StrReplace(StrSplit(Split[1], InstallName[1] "\")[-1], "\", "/")

    Split := StrSplit(PackageInfo.InstallName := InstallName[1], "_",, 2)
    PackageInfo.Author := Split[1]
    PackageInfo.Name := SubStr(Split[2], 1, InStr(Split[2], "_",,-1)-1)
    PackageInfo.InstallVersion := SubStr(Split[2], InStr(Split[2], "_",,-1)+1)
    PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name

    if g_PackageJson["dependencies"].Has(PackageInfo.PackageName) {
        DependencyInfo := g_PackageJson["dependencies"][PackageInfo.PackageName]
        if IsSemVer(DependencyInfo) || IsVersionSha(DependencyInfo) || IsVersionMD5(DependencyInfo) {
            PackageInfo.DependencyVersion := DependencyInfo
        } else if loc := InStr(DependencyInfo, "@",,-1) {
                PackageInfo.DependencyVersion := SubStr(DependencyInfo, loc+1)
                DependencyInfo := SubStr(DependencyInfo, 1, loc-1)
                if loc := InStr(PackageInfo.DependencyVersion, "+",,-1)
                    PackageInfo.DependencyHash := SubStr(PackageInfo.DependencyVersion, loc+1), PackageInfo.DependencyVersion := SubStr(PackageInfo.DependencyVersion, 1, loc-1)
        } else
            PackageInfo.DependencyVersion := "*"
    } else 
        PackageInfo.DependencyVersion := PackageInfo.InstallVersion

    if !PackageInfo.RepositoryType
        PackageInfo.RepositoryType := "github"
    if !PackageInfo.Repository
        PackageInfo.Repository := PackageInfo.PackageName

    ParseRepositoryData(PackageInfo)

    return PackageInfo        
}

DependencyInfoToPackageInfo(PackageName, DependencyInfo) {
    if IsSemVer(DependencyInfo) || IsVersionSha(DependencyInfo) || IsVersionMD5(DependencyInfo) {
        try {
            PackageInfo := SearchPackageByName(PackageName, 1)
        } catch {
            PackageInfo := PackageInfoBase()
        }
        PackageInfo.DependencyVersion := DependencyInfo
    } else if InStr(DependencyInfo, ":") || InStr(DependencyInfo, "/") {
        PackageInfo := InputToPackageInfo(DependencyInfo)
        PackageInfo.DependencyEntry := DependencyInfo
        PackageInfo.DependencyVersion := PackageInfo.Version, PackageInfo.Version := ""
    } else
        throw Error("Invalid dependency entry", -1, PackageName ":" DependencyInfo)
    PackageInfo.PackageName := PackageName
    Split := StrSplit(PackageName, "/",, 2)
    PackageInfo.Author := Split[1]
    PackageInfo.Name := Split[2]
    return PackageInfo
}

SearchPackageByName(Input, Skip := 0) {
    Split := StrSplit(Input, "/"), InputAuthor := ""
    if Split.Length = 2
        InputAuthor := Split[1], InputName := Split[2]
    else
        InputName := Split[1]

    if InputAuthor = "" {
        found := []
        if Skip != 1 {
            for Name, Info in QueryPackageDependencies() {
                if Name ~= "i)\/\Q" InputName "\E$"
                    found.Push(Info)
            }
        }
        if !found.Length {
            for Name, Info in g_Index {
                if Name ~= "i)\/\Q" InputName "\E$"
                    Split := StrSplit(Name, "/",,2), found.Push(MergeJsonInfoToPackageInfo(Info, PackageInfoBase(Split[1], Split[2])))
            }
        }
        if !found.Length
            throw Error("No matching package found in index nor dependencies", -1, InputName)
        if found.Length > 1
            return found
        else if g_Index.Has(found[1].PackageName)
            MergeJsonInfoToPackageInfo(g_Index[found[1].PackageName], found[1])
        return found[1]
    } else if Skip != 1 {
        for Name, Info in QueryPackageDependencies() {
            if Name = InputAuthor "/" InputName {
                if g_Index.Has(Info.PackageName)
                    MergeJsonInfoToPackageInfo(g_Index[Info.PackageName], Info)
                return Info
            }
        }
    }
    PackageName := Input, PackageInfo := PackageInfoBase(InputAuthor, InputName)
    if g_Index.Has(PackageName) {
        MergeJsonInfoToPackageInfo(g_Index[PackageName], PackageInfo)
    } else {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", "https://api.github.com/repos/" InputAuthor "/" InputName, true)
        whr.SetRequestHeader("Accept", "application/vnd.github+json")
        whr.Send()
        whr.WaitForResponse()
        res := whr.ResponseText
        if InStr(whr.ResponseText, '"name"') {
            MergeJsonInfoToPackageInfo(Map("name", PackageName, "repository", Map("type", "github", "url", InputAuthor "/" InputName), "author", InputAuthor), PackageInfo)
        } else
            throw ValueError("Package not found", -1, PackageInfo.Name)
    }
    return PackageInfo
}

; Update=0 means install and skip if already installed
; Update=1 means allow update if package is already installed, but skip if is not installed
; Update=2 means allow update and install if not installed
InstallPackage(Package, Update:=0) {
    global g_PackageJson, g_InstalledPackages, g_LibDir
    CurrentlyInstalled := Mapi()
    if !(Package is Object) {
        try PackageInfo := InputToPackageInfo(Package)
        catch as err {
            WriteStdOut err.Message (err.Extra ? ": " err.Extra : "")
            return
        }
    } else
        PackageInfo := Package
    if Update && !g_InstalledPackages.Has(PackageInfo.PackageName) && !PackageInfo.IsMain
        Update := 0
    WriteStdOut 'Starting ' (Update ? "update" : "install") ' of package "' (Package is Object ? Package.PackageName : Package) '"'
    Result := 0, DownloadResult := 0
    TempDir := A_ScriptDir "\~temp-" Random(100000000, 1000000000)
    if DirExist(TempDir)
        DirDelete(TempDir, true)
    DirCreate(TempDir)

    for PackageName, PackageInfo in g_InstalledPackages
        CurrentlyInstalled[PackageName "@" PackageInfo.InstallVersion] := 1

    if (Update = 1) && !g_InstalledPackages.Has(PackageInfo.PackageName) && !PackageInfo.IsMain {
        WriteStdOut 'Cannot update package "' PackageInfo.PackageName '" as it is not installed.'
        goto Cleanup
    }

    if Update && PackageInfo.DependencyVersion && !InStr(Package, "@") {
        PackageInfo.Version := PackageInfo.DependencyVersion
    }

    if g_Switches["main"] != "" {
        PackageInfo.Main := g_Switches["main"]
        if !g_Index.Has(PackageInfo.PackageName) {
            PackageInfo.Name := StrSplit(g_Switches["main"], "/")[-1] 
            PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name
        }
    }
    if g_Switches["files"].Length
        PackageInfo.Files := g_Switches["files"]

    if PackageInfo.Main {
        if !PackageInfo.Files.Length
            PackageInfo.Files := [PackageInfo.Main]

        MainFileInFiles := false
        for PackageFile in PackageInfo.Files {
            if PackageFile = PackageInfo.Main {
                MainFileInFiles := true
                break
            }
        }
        if !MainFileInFiles
            PackageInfo.Files.Push(PackageInfo.Main)
    }

    if PackageInfo.IsMain {
        PrevWorkingDir := A_WorkingDir
        try {
            VerifyPackageIsDownloadable(PackageInfo)
            if IsPackageInstalled(PackageInfo, g_InstalledPackages, [TempDir, g_LibDir])
                goto Cleanup
            FinalDirName := DownloadSinglePackage(PackageInfo, TempDir, g_LibDir)
            A_WorkingDir := TempDir "\" FinalDirName
            Dependencies := Map()
            LibDir := FindLibDir()
            if FileExist(LibDir "\packages.ahk") {
                Dependencies := QueryPackageDependencies(TempDir "\" FinalDirName, "packages.ahk")
            } else if FileExist(".\package.json") {
                Dependencies := QueryPackageDependencies(TempDir "\" FinalDirName, "packages.json")
            } else {
                if g_Index.Has(PackageInfo.PackageName) && g_Index[PackageInfo.PackageName].Has("dependencies")
                    Dependencies := g_Index[PackageInfo.PackageName]["dependencies"]
            }
            if Dependencies.Count {
                for Dependency, Version in Dependencies
                    InstallPackage(Dependency "@" StrSplitLast(Version, "@")[-1])
            }
            g_PackageJson := LoadPackageJson()
            DownloadResult := true
            A_WorkingDir := PrevWorkingDir
        } catch as err {
            WriteStdOut "Failed to download package"
            WriteStdOut "`t" err.Message (err.Extra ? ": " err.Extra : "")
            A_WorkingDir := PrevWorkingDir
            goto Cleanup
        }
    } else {
        try DownloadResult := DownloadPackageWithDependencies(PackageInfo, TempDir, g_InstalledPackages, Update)
        catch as err {
            WriteStdOut "Failed to download package with dependencies"
            WriteStdOut "`t" err.Message (err.Extra ? ": " err.Extra : "")
            goto Cleanup
        }
    }
    if DownloadResult is Integer && DownloadResult > 0 && !PackageInfo.IsMain {
        Result := DownloadResult = 1
        goto Cleanup
    }

    if PackageInfo.IsMain {
        DirMove(TempDir "\" FinalDirName, A_WorkingDir, 2)
    } else
        DirMove(TempDir, g_LibDir, 2)

    PackageJson := LoadPackageJson()

    if FileExist(g_LibDir "\packages.ahk")
        IncludeFileContent := FileRead(g_LibDir "\packages.ahk")
    else
        IncludeFileContent := "; Avoid modifying this file manually`n`n"

    AddedIncludesString := ""
    for IncludePackageName, Include in g_InstalledPackages {
        if CurrentlyInstalled.Has(IncludePackageName "@" Include.InstallVersion)
            continue
        if !PackageJson["dependencies"].Has(IncludePackageName) || g_Switches["force"]
            PackageJson["dependencies"][IncludePackageName] := Include.DependencyEntry ? Include.DependencyEntry : Include.DependencyVersion ? Include.DependencyVersion : IsSemVer(Include.Version) && !(Include.Version ~= "^[~^><=]") ? "^" Include.Version : Include.Version
        if Update
            WriteStdOut 'Package successfully updated to "' IncludePackageName "@" Include.InstallVersion '".'
        else
            WriteStdOut 'Package "' IncludePackageName "@" Include.InstallVersion '" successfully installed.'

        if Include.HasProp("Main") && Include.Main {
            Addition := "#include .\" Include.InstallName "\" Include.Main (Include.DependencyEntry != "" ? " `; Source: " Include.DependencyEntry : "") "`n"
            if !InStr(IncludeFileContent, Addition)
                IncludeFileContent .= Addition, AddedIncludesString .= Addition
        }
    }

    if AddedIncludesString
        WriteStdOut "`n" (Update ? "Updated" : "Installed") " packages include directives:`n" StrReplace(AddedIncludesString, "#include .\", "#include .\" g_LibDir "\")

    if !PackageJson["dependencies"].Count
        PackageJson.Delete("dependencies")

    if !PackageInfo.IsMain
        FileOpen("package.json", 0x1).Write(JSON.Dump(PackageJson, true))
    FileOpen(g_LibDir "\packages.ahk", 0x1).Write(IncludeFileContent)
    g_PackageJson := LoadPackageJson()

    Result := 1

    Cleanup:
    try DirDelete(TempDir, 1)
    return Result
}

DownloadPackageWithDependencies(PackageInfo, TempDir, Includes, CanUpdate:=false, MarkedForRemove:=[]) {
    IsVersioned := PackageInfo.Version || (PackageInfo.RepositoryType = "archive")

    if CanUpdate && !PackageInfo.Version && PackageInfo.PackageName != "" && g_PackageJson["dependencies"].Has(PackageInfo.PackageName) {
        PackageInfo.Version := g_PackageJson["dependencies"][PackageInfo.PackageName]
    }

    if PackageInfo.IsMain {
        PrevWorkingDir := A_WorkingDir
        A_WorkingDir := TempDir
        goto DownloadPackage
    }

    ; First download dependencies listed in index.json, except if we are updating our package
    if !CanUpdate && PackageInfo.Dependencies.Count {
        for DependencyName, DependencyVersion in PackageInfo.Dependencies {
            if !DownloadPackageWithDependencies(DependencyInfoToPackageInfo(DependencyName, DependencyVersion), TempDir, Includes)
                throw Error("Failed to install dependency", -1, DependencyName "@" DependencyVersion)
        }
    }

    if !IsVersioned && !CanUpdate && PackageInfo.Version {
        if Includes.Has(PackageInfo.PackageName) && (Include := Includes[PackageInfo.PackageName]) && (DirExist(TempDir "\" Include.InstallName) || DirExist(g_LibDir "\" Include.InstallName)) {
            WriteStdOut 'Package "' Include.InstallName '" already installed, skipping...'
            PackageInfo.InstallName := Include.InstallName
            return Include
        }
    }

    DownloadPackage:

    VerifyPackageIsDownloadable(PackageInfo)
    if !IsVersioned && IsPackageInstalled(PackageInfo, Includes, [TempDir, g_LibDir]) && IsVersionCompatible(PackageInfo.Version, "=" PackageInfo.InstallVersion) {
        if CanUpdate
            WriteStdOut 'Package "' PackageInfo.PackageName "@" PackageInfo.Version '" has no matching updates available'
        else
            WriteStdOut 'Package "' PackageInfo.PackageName "@" PackageInfo.Version '" is already installed'
        return 0
    }

    FinalDirName := DownloadSinglePackage(PackageInfo, TempDir, g_LibDir)

    if FinalDirName is Integer
        return FinalDirName

    if IsVersioned { ; A specific version was requested, in which case force the install
        if Includes.Has(PackageInfo.PackageName) && (Include := Includes[PackageInfo.PackageName]) && DirExist(g_LibDir "\" Include.InstallName) {
            InstalledPackages := QueryInstalledPackages()
            ForceRemovePackageWithDependencies(Include, InstalledPackages, g_LibDir)
            Includes.Delete(PackageInfo.PackageName)
            if !IsVersionCompatible(PackageInfo.Version, PackageInfo.DependencyVersion)
                PackageInfo.DependencyVersion := PackageInfo.Version
        }
    } else if CanUpdate {
        if Includes.Has(PackageInfo.PackageName) && (Include := Includes[PackageInfo.PackageName]) && DirExist(g_LibDir "\" Include.InstallName) && IsVersionCompatible(PackageInfo.Version, "^" Include.DependencyVersion) {
            ForceRemovePackage(Include, g_LibDir, false)
            Includes.Delete(PackageInfo.PackageName)
        }
    }

    if PackageInfo.Files.Length {
        DirCreate(TempDir "\~" FinalDirName)
        MainFile := Trim(StrReplace(PackageInfo.Main, "/", "\"), "\/")
        if !FileExist(TempDir "\" FinalDirName "\" MainFile) {
            Loop files TempDir "\" FinalDirName "\*.ah*", "R" {
                if A_LoopFileName = MainFile {
                    MainFile := StrSplit(A_LoopFileFullPath, TempDir "\" FinalDirName "\",, 2)[-1]
                    break
                }
            }
        }
        if PackageInfo.Files.Length = 1 && PackageInfo.Files[1] ~= "(?<!\*)\.ahk?\d?$" {
            PackageInfo.Main := StrSplit(MainFile, "\")[-1]
            FileMove(TempDir "\" FinalDirName "\" MainFile, TempDir "\~" FinalDirName "\" PackageInfo.Main)
        } else {
            Loop Files TempDir, "D" {
                TempDirFullPath := A_LoopFileFullPath
                break
            }
            for Pattern in PackageInfo.Files {
                Pattern := Trim(StrReplace(Pattern, "/", "\"), "\/")
                Loop files TempDirFullPath "\" FinalDirName "\" Pattern, "DF" {
                    FileName := StrReplace(A_LoopFileFullPath, TempDirFullPath "\" FinalDirName,,,,1)
                    FileName := Trim(StrReplace(FileName, "/", "\"), "\/")

                    DirName := "", SplitName := StrSplit(FileName, "\")
                    if FileExist(TempDirFullPath "\" FinalDirName "\" FileName)
                        SplitName.Pop()
                    for SubDir in SplitName {
                        DirName .= SubDir "\"
                        if !DirExist(TempDirFullPath "\~" FinalDirName "\" DirName)
                            DirCreate(TempDirFullPath "\~" FinalDirName "\" DirName)
                    }

                    if DirExist(A_LoopFileFullPath)
                        DirMove(A_LoopFileFullPath, TempDir "\~" FinalDirName "\" FileName, 1)
                    else
                        FileMove(A_LoopFileFullPath, TempDir "\~" FinalDirName "\" FileName)
                }
            }
        }
        
        if !FileExist(TempDir "\~" FinalDirName "\" MainFile) {
            PackageInfo.Main := StrSplit(MainFile, "\")[-1]
            if DirExist(TempDir "\" FinalDirName "\" PackageInfo.Main)
                DirMove(TempDir "\" FinalDirName "\" PackageInfo.Main, TempDir "\~" FinalDirName, 2)
            else if FileExist(TempDir "\" FinalDirName "\" PackageInfo.Main)
                FileMove(TempDir "\" FinalDirName "\" PackageInfo.Main, TempDir "\~" FinalDirName "\" PackageInfo.Main)
        }
        if FileExist(TempDir "\" FinalDirName "\LICENSE")
            FileMove(TempDir "\" FinalDirName "\LICENSE", TempDir "\~" FinalDirName "\LICENSE")
        DirDelete(TempDir "\" FinalDirName, 1)
        DirMove(TempDir "\~" FinalDirName, TempDir "\" FinalDirName)
    }

    AddMainInclude:

    if !PackageInfo.Main {
        Loop Files TempDir "\" FinalDirName "\*.ah*" {
            if (A_LoopFileName = (PackageInfo.Name "." A_LoopFileExt)) || (A_LoopFileName ~= "^(main|export)\.ah") || (PackageInfo.Name ~= "\.ahk?\d?$" && StrSplitLast(A_LoopFileName, ".")[1] = StrSplitLast(PackageInfo.Name, ".")[1]) {
                PackageInfo.Main := A_LoopFileFullPath
                break
            }
        }
        if !PackageInfo.Main && DirExist(TempDir "\" FinalDirName "\Lib") {
            Loop Files TempDir "\" FinalDirName "\Lib\*.ah*" {
                if (A_LoopFileName = (PackageInfo.Name "." A_LoopFileExt)) || (A_LoopFileName ~= "^(main|export)\.ah") || (PackageInfo.Name ~= "\.ahk?\d?$" && StrSplitLast(A_LoopFileName, ".")[1] = StrSplitLast(PackageInfo.Name, ".")[1]) {
                    PackageInfo.Main := A_LoopFileFullPath
                    break
                }
            }
        }
        if !PackageInfo.Main {
            Loop Files TempDir "\" FinalDirName "\*.ah*", "R" {
                if PackageInfo.Main
                    throw Error("Unable to lock onto a specific main file", -1)
                PackageInfo.Main := A_LoopFileFullPath
                if PackageInfo.RepositoryType = "archive"
                    break
            }
        }
        PackageInfo.Main := LTrim(StrSplit(PackageInfo.Main, FinalDirName,, 2)[-1], "\")
    }

    PackageInfo.InstallVersion := PackageInfo.Version
    PackageInfo.InstallHash := PackageInfo.Hash
    PackageInfo.DependencyVersion := IsSemVer(PackageInfo.Version) ? (PackageInfo.DependencyVersion ? PackageInfo.DependencyVersion : ((PackageInfo.Version ~= "^[~^><=]") ? "" : "^") PackageInfo.Version) : PackageInfo.Version

    if !PackageInfo.IsMain {
        PackageInfo.Main := Trim(StrReplace(PackageInfo.Main, "/", "\"), "\/")
        Includes[PackageInfo.PackageName] := PackageInfo
    } 

    if DirExist(TempDir "\" FinalDirName) && FileExist(TempDir "\" FinalDirName "\package.json") {
        if PackageInfo.IsMain {
            LibDir := FindLibDir(TempDir "\" FinalDirName)
            TempDir .= "\" FinalDirName "\" LibDir
        }

        PackageJson := LoadJson(TempDir "\" FinalDirName "\package.json")
        if PackageJson.Has("dependencies") {
            for DependencyName, DependencyVersion in PackageJson["dependencies"]
                DownloadPackageWithDependencies(DependencyName "@" DependencyVersion, TempDir, Includes)
        }
    }

    return PackageInfo
}

VerifyPackageIsDownloadable(PackageInfo) {
    if PackageInfo.RepositoryType = "github" && IsVersionSha(PackageInfo.Version) {
        if !(PackageInfo.Main && PackageInfo.Files.Length) {
            Repo := StrSplit(PackageInfo.Repository, "/")
            PackageInfo.ZipName := Repo[1] "_" Repo[2] "_" PackageInfo.Version ".zip"
            PackageInfo.SourceAddress := "https://github.com/" Repo[1] "/" Repo[2] "/archive/" PackageInfo.Version ".zip"
        }
    } else if PackageInfo.RepositoryType = "github" {
        if !PackageInfo.Repository
            throw Error("No GitHub repository found in index.json", -1)
        Repo := StrSplit(PackageInfo.Repository, "/")
        if !(releases := QueryGitHubReleases(PackageInfo.Repository)) || !(releases is Array) || !releases.Length {
            ; No releases found. Try to get commit hash instead.
            if (commits := QueryGitHubCommits(PackageInfo.Repository)) && commits is Array && commits.Length
                PackageInfo.Version := SubStr(commits[1]["sha"], 1, 7)
            else
                throw Error("Unable to find releases or commits for the specified GitHub repository", -1, PackageInfo.PackageName)

            WriteStdOut("No GitHub releases found, falling back to the default branch.")
            if IsGithubMinimalInstallPossible(PackageInfo)
                return

            ZipName := (repo.Length = 3 ? repo[3] : QueryGitHubRepo(PackageInfo.Repository)["default_branch"]) ".zip"
            PackageInfo.SourceAddress := "https://github.com/" Repo[1] "/" Repo[2] "/archive/refs/heads/" ZipName
            PackageInfo.ZipName := Repo[1] "_" Repo[2] "_" PackageInfo.Version "-" ZipName
        } else {
            if !(release := FindMatchingGithubReleaseVersion(releases, PackageInfo.Version))
                throw Error("No matching version found among GitHub releases")

            PackageInfo.Version := release["tag_name"]
            PackageInfo.ZipName := Repo[1] "_" Repo[2] "_" PackageInfo.Version ".zip"
            PackageInfo.SourceAddress := release["zipball_url"]
        }
    } else if PackageInfo.RepositoryType = "archive" {
        PackageInfo.Version := A_YYYY A_MM A_DD SubStr(MD5(PackageInfo.Repository), 1, 12)
        PackageInfo.ZipName := "archive_" PackageInfo.Version (RegExMatch(PackageInfo.Repository, "\.tar\.gz$") ? ".tar.gz" : "." StrSplit(PackageInfo.Repository, ".")[-1])
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
    } else if PackageInfo.RepositoryType = "forums" {
        if !PackageInfo.ThreadId {
            ParseRepositoryData(PackageInfo)
        }
        if PackageInfo.Version != "latest" && !PackageInfo.Hash {
            WriteStdOut('Querying versions from Wayback Machine snapshots of AutoHotkey forums thread with id ' PackageInfo.ThreadId)
            Matches := QueryForumsReleases(PackageInfo)
            if !Matches.Length
                throw Error("No Wayback Machine snapshots found for the forums thread with id " PackageInfo.ThreadId (PackageInfo.Post ? ", post id " PackageInfo.Post : "") (PackageInfo.Start ? ", start number " PackageInfo.Start : ""), -1)
            LatestEntry := {Repository:"", Version:0}
            for Entry in Matches {
                if IsVersionCompatible(Entry.Version, PackageInfo.Version) && Entry.Version > LatestEntry.Version
                    LatestEntry := Entry
            }
            if LatestEntry.Version = 0
                throw Error("No compatible versions found in Wayback Machine. Use version @latest to download directly from the forums.", -1)
            PackageInfo.Version := LatestEntry.Version
            PackageInfo.Repository := "http://web.archive.org/web/" PackageInfo.Version "/" LatestEntry.Repository
        }
    } else if PackageInfo.RepositoryType != "archive"
        throw ValueError("Unknown package source", -1, PackageInfo.RepositoryType)
}

IsPackageInstalled(PackageInfo, Includes, Dirs) {
    if Includes.Has(PackageInfo.PackageName) {
        for Dir in Dirs
            if DirExist(Dir "\" Includes[PackageInfo.PackageName].InstallName)
                return true
    }
    return false
}

; Returns 1 if package is already installed, otherwise FinalDirName
DownloadSinglePackage(PackageInfo, TempDir, LibDir) {
    static TempDownloadDir := "~downloaded_package"

    try DirDelete(TempDir "\" TempDownloadDir, 1)
    DirCreate(TempDir "\" TempDownloadDir)

    if PackageInfo.RepositoryType = "github" && IsGithubMinimalInstallPossible(PackageInfo) {
        GithubDownloadMinimalInstall(PackageInfo, TempDir "\" TempDownloadDir)
        goto AfterDownload
    } else if PackageInfo.RepositoryType = "gist" {
        gist := PackageInfo.Gist

        if !PackageInfo.Author
            PackageInfo.Author := gist["owner"]["login"]
        if PackageInfo.Main {
            MainFound := false, MainNames := ""
            for MainName, Info in gist["files"] {
                MainNames .= '"' MainName '", '
                if MainName = PackageInfo.Main {
                    MainFound := true
                    if !PackageInfo.Version || PackageInfo.Version = "latest" || PackageInfo.Version = "*" {
                        FileAppend(Info["content"], TempDir "\" TempDownloadDir "\" PackageInfo.Main)
                        goto AfterDownload
                    }
                    break
                }
            }
            if !MainFound
                throw Error("No matching file found in gist", -1, '"' PackageInfo.Main '" not found among Gist filenames [' Trim(MainNames, ", ") "]")
        } else {
            for MainName, Info in gist["files"] {
                PackageInfo.Main := PackageInfo.Name := Info["filename"]
                break
            }
        }
        PackageInfo.SourceAddress := "https://gist.github.com/raw/" PackageInfo.Repository "/" PackageInfo.FullVersion "/" PackageInfo.Name
        PackageInfo.DependencyEntry := "gist:" PackageInfo.Repository "/" PackageInfo.Main "@" ((IsVersionSha(PackageInfo.DependencyVersion) ? "" : PackageInfo.DependencyVersion) || PackageInfo.Version || PackageInfo.InstallVersion)
        if !PackageInfo.PackageName
            PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name
        WriteStdOut('Downloading gist as package "' PackageInfo.PackageName '@' PackageInfo.Version '"')
        Download PackageInfo.SourceAddress, TempDir "\" TempDownloadDir "\" PackageInfo.Name
        FileAppend(JSON.Dump(Map("repository", Map("type", "gist", "url", PackageInfo.DependencyEntry), "author", PackageInfo.Author, "name", PackageInfo.PackageName, "version", PackageInfo.FullVersion), true), TempDir "\" TempDownloadDir "\package.json")
        goto AfterDownload
    } else if PackageInfo.RepositoryType = "forums" {
        if PackageInfo.Version = "latest" || PackageInfo.Hash {
            WriteStdOut('Downloading from AutoHotkey forums thread ' PackageInfo.ThreadId ' code box ' PackageInfo.CodeBox)
            PackageInfo.Repository := "https://www.autohotkey.com/boards/viewtopic.php?t=" PackageInfo.ThreadId (PackageInfo.Start ? "&start=" PackageInfo.Start : "") (PackageInfo.Post ? "&p=" PackageInfo.Post : "")
        } else {
            WriteStdOut('Downloading from Wayback Machine snapshot ' PackageInfo.Version ' of AutoHotkey forums thread ' PackageInfo.ThreadId (PackageInfo.Post ? ' post id ' PackageInfo.Post : "") ' code box ' PackageInfo.CodeBox)
        }

        Page := DownloadURL(PackageInfo.Repository)
        if PackageInfo.Name = "" {
            if RegExMatch(Page, 'topic-title"><a[^>]*>(.+?)</a>', &title:="") {
                if RegExMatch(MainName := title[1], "(?:\[[^]]+\])?\s*(((?:\w\S*)\s*)+)(?=\s|\W|$)", &cleantitle:="")
                    MainName := cleantitle[1]
                MainName := Trim(RegExReplace(MainName, '[<>:"\/\|?*\s]', "-"), "- ")
                MainName := RegExReplace(MainName, "i)(^class-)|(\-class$)")
                PackageInfo.Name := MainName
            } else
                PackageInfo.Name := PackageInfo.ThreadId
        }
        if PackageInfo.Post && RegExMatch(Page, '<div id="p' PackageInfo.Post '([\w\W]+?)<div id="p\d+', &Post:="") {
            Page := Post[1]
        }
        if PackageInfo.Author = "" && RegExMatch(Page, 'class="username(?:-coloured)?">(.+?)<\/a>', &author:="")
            PackageInfo.Author := RegExReplace(author[1], '[<>:"\/\|?*]')
        else if PackageInfo.Author = ""
            PackageInfo.Author := "Unknown"
        CodeMatches := RegExMatchAll(Page, "<code [^>]*>([\w\W]+?)<\/code>")
        Code := UnHTM(CodeMatches[PackageInfo.CodeBox][1])
        if !PackageInfo.PackageName
            PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name

        if !PackageInfo.Version || PackageInfo.Version = "latest" || PackageInfo.Hash {
            PackageInfo.Version := A_YYYY A_MM A_DD A_Hour A_Min A_Sec "+" (Hash := SubStr(MD5(Code), 1, 12))
            if PackageInfo.Hash && Hash != PackageInfo.Hash
                throw Error("Download from forums succeeded, but there was a package hash mismatch", -1, "Found " Hash " but expected " PackageInfo.Hash)
        }

        FileAppend(Code, TempDir "\" TempDownloadDir "\" PackageInfo.Name ".ahk")

        PackageInfo.DependencyEntry := "forums:t=" PackageInfo.ThreadId (PackageInfo.Start ? "&start=" PackageInfo.Start : "") (PackageInfo.Post ? "&p=" PackageInfo.Post : "") "&codebox=" PackageInfo.CodeBox "@" PackageInfo.Version
        PackageInfo.Version := RegExReplace(PackageInfo.Version, "\+.*$")
        FileAppend(JSON.Dump(Map("repository", Map("type", "forums", "url", "https://www.autohotkey.com/boards/viewtopic.php?t=" PackageInfo.ThreadId "&codebox=" PackageInfo.CodeBox), "author", PackageInfo.Author, "name", PackageInfo.PackageName, "version", PackageInfo.Version), true), TempDir "\" TempDownloadDir "\package.json")
        goto AfterDownload
    } else if PackageInfo.RepositoryType = "github" {
        if !PackageInfo.DependencyEntry && !g_Index.Has(PackageInfo.PackageName) {
            Version := PackageInfo.DependencyVersion || PackageInfo.Version || PackageInfo.InstallVersion
            PackageInfo.DependencyEntry := "github:" PackageInfo.Repository "@" (IsSemVer(Version) && !(Version ~= "^[~^><=]") ? "^" Version : Version)
        }
    }

    WriteStdOut('Downloading package "' PackageInfo.PackageName '"')
    ZipName := PackageInfo.ZipName
    if !FileExist(g_CacheDir "\" ZipName)
        Download PackageInfo.SourceAddress, g_CacheDir "\" ZipName

    if PackageInfo.RepositoryType = "archive"
        PackageInfo.Version := SubStr(HashFile(g_CacheDir "\" ZipName, 3), 1, 7)

    DirCopy g_CacheDir "\" ZipName, TempDir "\" TempDownloadDir, true

    Loop Files TempDir "\" TempDownloadDir "\*.*", "D" {
        if PackageInfo.RepositoryType = "archive"
            PackageInfo.Name := PackageInfo.Name || A_LoopFileName, PackageInfo.Author := PackageInfo.Author || "Archive", PackageInfo.PackageName := PackageInfo.PackageName || PackageInfo.Author "/" PackageInfo.Name
        DirMove(A_LoopFileFullPath, TempDir "\" TempDownloadDir, 2)
        break
    }

    if !PackageInfo.IsMain && FileExist(TempDir "\" TempDownloadDir "\package.json") && !g_Index.Has(PackageInfo.PackageName) {
        PackageJson := LoadPackageJson(TempDir "\" TempDownloadDir)
        if PackageJson.Has("name") {
            if InStr(PackageJson["name"], "/") {
                PackageInfo.PackageName := PackageJson["name"]
                Split := ParsePackageName(PackageJson["name"])
                PackageInfo.Name := Split.Name, PackageInfo.Author := Split.Author
            } else {
                PackageInfo.Name := PackageJson["name"], PackageInfo.PackageName := PackageInfo.PackageName || PackageInfo.Author "/" PackageInfo.Name
            }
        }
        if PackageJson.Has("version")
            PackageInfo.Version := PackageJson["version"]
    }

    AfterDownload:

    FinalDirName := PackageInfo.Author "_" PackageInfo.Name "_" PackageInfo.Version
    PackageInfo.InstallName := FinalDirName

    if PackageInfo.RepositoryType = "forums" && PackageInfo.Hash != "" {
        Loop files LibDir "\*.*", "DR" {
            if RegExMatch(A_LoopFileName, "^\Q" PackageInfo.Author "_" PackageInfo.Name "_\E.*\+\Q" PackageInfo.Hash "\E$") {
                FinalDirName := A_LoopFileName
                break
            }
        }
    }

    if DirExist(TempDir "\" FinalDirName) || DirExist(LibDir "\" FinalDirName) {
        WriteStdOut 'Package "' FinalDirName '" already installed or up-to-date, skipping...'
        DirDelete(TempDir "\" TempDownloadDir, true)
        return 1
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
        PackageInfo.MainPath := StrSplit(PackageInfo.Main, "\")[-1], PackageInfo.Main := StrSplit(PackageInfo.Main, "/")[-1]
        PackageInfo.DependencyEntry := "github:" PackageInfo.Repository "@" (PackageInfo.DependencyVersion || PackageInfo.Version || PackageInfo.InstallVersion)
        try Download("https://github.com/" Repo[1] "/" Repo[2] "/raw/" PackageInfo.Version "/"  PackageInfo.MainPath, Path "\" PackageInfo.Main)
        catch
            throw Error("Download failed", -1, '"' Path "\" PackageInfo.Main '@' PackageInfo.Version '" from GitHub repo "' Repo[1] "/" Repo[2] '"')
        try Download("https://github.com/" Repo[1] "/" Repo[2] "/raw/" PackageInfo.Version "/LICENSE", Path "\LICENSE")
        if InStr(FileRead(Path "\LICENSE"), "<!DOCTYPE html>")
            FileDelete(Path "\LICENSE")
        return 1
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
        PackageInfo.DependencyEntry := "github:" PackageInfo.Repository "@" (PackageInfo.DependencyVersion || PackageInfo.Version || PackageInfo.InstallVersion)
    }
    return 1
}

ForceRemovePackage(PackageInfo, LibDir, RemoveDependencyEntry:=true) {
    global g_PackageJson
    DirDelete(".\" LibDir "\" PackageInfo.InstallName, true)
    if FileExist(".\" LibDir "\packages.ahk") {
        OldPackages := FileRead(".\" LibDir "\packages.ahk")
        NewPackages := RegExReplace(OldPackages, ".*\Q\" PackageInfo.InstallName "\\E.*\n\r?",,, 1)
        if OldPackages != NewPackages
            FileOpen(".\" LibDir "\packages.ahk", "w").Write(NewPackages)
    }
    if FileExist(".\package.json") && RemoveDependencyEntry {
        PackageJson := LoadPackageJson(, &OldContent)
        if PackageJson["dependencies"].Has(PackageInfo.PackageName) {
            PackageJson["dependencies"].Delete(PackageInfo.PackageName)
            NewContent := JSON.Dump(PackageJson, true)
            if OldContent != NewContent && NewContent {
                FileOpen(".\package.json", "w").Write(NewContent)
                g_PackageJson := LoadPackageJson()
            }
        }
    }
    if g_InstalledPackages.Has(PackageInfo.PackageName)
        g_InstalledPackages.Delete(PackageInfo.PackageName)
}

ForceRemovePackageWithDependencies(PackageInfo, InstalledPackages, LibDir, RemoveDependencyEntry:=true) {
    ForceRemovePackage(PackageInfo, LibDir, RemoveDependencyEntry)
    Dependencies := QueryInstalledPackageDependencies(PackageInfo, InstalledPackages, LibDir)
    for Dependency, Version in Dependencies {
        DependencyInfo := DependencyInfoToPackageInfo(Dependency, Version)
        ForceRemovePackage(DependencyInfo, LibDir, RemoveDependencyEntry)
        for i, InstalledPackage in InstalledPackages {
            if (InstalledPackage.PackageName = DependencyInfo.PackageName && InstalledPackage.Version = DependencyInfo.Version) {
                InstalledPackage.RemoveAt(i)
                break
            }
        }
        ForceRemovePackageWithDependencies(DependencyInfo, InstalledPackages, LibDir, RemoveDependencyEntry)
    }
}

RemovePackage(PackageName, RemoveDependencyEntry:=true) {
    PackageInfo := ParsePackageName(PackageName)
    InstalledPackages := QueryInstalledPackages()

    if !(Matches := FindMatchingInstalledPackages(PackageInfo, InstalledPackages))
        return

    if !Matches.Length {
        WriteStdOut "No such package installed"
    } else if Matches.Length = 1 {
        Match := Matches[1]

        if !g_Switches["force"] {
            Dependencies := QueryInstalledPackageDependencies(Match, InstalledPackages, g_LibDir)
            if Dependencies.Length {
                DepString := 'Cannot remove package "' Match.PackageName "@" Match.InstallVersion '" as it is depended on by: '
                for Dependency in Dependencies
                    DepString .= "`n`t" Dependency.PackageName "@" Dependency.DependencyVersion

                WriteStdOut DepString
                return
            }
        }

        ForceRemovePackage(Match, g_LibDir, RemoveDependencyEntry)
        WriteStdOut 'Package "' Match.PackageName "@" Match.InstallVersion '" removed!'
    } else {
        WriteStdOut "Multiple matches found:"
        for Match in Matches
            WriteStdOut "`t" Match.PackageName "@" Match.InstallVersion
    }
}

FindMatchingInstalledPackages(PackageInfo, InstalledPackages) {
    if !FileExist("package.json")
        return WriteStdOut("No package.json found")

    ; Validate that the removed package is a dependency of the project
    if !(g_PackageJson["dependencies"].Count)
        return WriteStdOut("No dependencies found in package.json, cannot remove package")

    if InstalledPackages.Has(PackageInfo.PackageName) && VerCompare(InstalledPackages[PackageInfo.PackageName].InstallVersion, PackageInfo.Version)
        return [InstalledPackages[PackageInfo.PackageName]]

    Matches := []
    for InstalledName, InstalledInfo in InstalledPackages {
        if InstalledInfo.Name != PackageInfo.Name
            continue
        Matches.Push(InstalledInfo)
    }
    /*
    if Matches.Length > 1 {
        Backup := Matches, Matches := []
        for Match in Backup {
            if !VerCompare(Match.Version, PackageInfo.Version)
                Matches.Push(Match)
        }
    }
    */
    if Matches.Length > 1 {
        Backup := Matches, Matches := []
        for Match in Backup {
            if Match.Author = PackageInfo.Author
                Matches.Push(Match)
        }
    }
    return Matches
}

QueryInstalledPackageDependencies(PackageInfo, InstalledPackages, LibDir) {
    DependencyList := []
    for _, InstalledPackage in InstalledPackages {
        if InstalledPackage.InstallName = PackageInfo.InstallName
            continue
        PackageDir := A_WorkingDir "\" LibDir "\" InstalledPackage.InstallName
        Dependencies := Map()
        if FileExist(PackageDir "\package.json") {
            Dependencies := LoadPackageJson(PackageDir)["dependencies"]
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
    global g_Index := Mapi()
    Index := LoadJson(A_ScriptDir "\assets\index.json")
    for PackageName, Info in Index {
        if !IsObject(Info)
            continue
        if !Info.Has("author")
            Info["author"] := StrSplit(PackageName, "/")[1]
        if !Info.Has("repository")
            Info["repository"] := Map("type", "github", "url", PackageName)
        else
            StandardizeRepositoryInfo(Info)
        if (!Info.Has("main") || Info["main"] = "") && Info.Has("files") && Info["files"].Length = 1 && Info["files"][1] ~= "\.ahk?\d?$"
            Info["main"] := Info["files"][1]
        if !Info.Has("main")
            Info["main"] := ""
        g_Index[PackageName] := Info
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
    Packages := QueryInstalledPackages()
    for _, Package in Packages
        WriteStdOut Package.PackageName "@" Package.InstallVersion
    else
        WriteStdOut "No packages installed"
}

QueryInstalledPackages(path := ".\") {
    PackageJson := path = ".\" ? g_PackageJson : LoadPackageJson(path)
    path := Trim(path, "\/") "\"
    LibDir := FindLibDir(path)
    Packages := Mapi()
    if !FileExist(path LibDir "\packages.ahk")
        return Packages

    Loop parse FileRead(path LibDir "\packages.ahk"), "`n", "`r" {
        if !(A_LoopField ~= "^\s*#include")
            continue

        Split := StrSplit(A_LoopField, "\")
        for Part in Split {
            if !RegExMatch(Part, "^.+_.+_.+$")
                continue
            if !DirExist(path LibDir "\" Part)
                continue
            PackageInfo := InstallInfoToPackageInfo(A_LoopField)
            if !PackageJson["dependencies"].Has(PackageInfo.PackageName)
                continue
            Packages[PackageInfo.PackageName] := PackageInfo
            break
        }
    }

    return Packages
}

QueryPackageDependencies(path := ".\", From := "") {
    path := Trim(path, "\/") "\"
    LibDir := FindLibDir(path)
    Packages := Mapi()
    if !From || From = "package.json" {
        PackageJson := path = ".\" ? g_PackageJson : LoadPackageJson(path)
        for PackageName, VersionRange in PackageJson["dependencies"] {
            Packages[PackageName] := DependencyInfoToPackageInfo(PackageName, VersionRange)
        }
    }
    if !From || From = "packages.ahk" {
        if FileExist(path LibDir "\packages.ahk") {
            for Include in ReadIncludesFromFile(path LibDir "\packages.ahk") {
                if Packages.Has(Include.PackageName) {
                    Packages[Include.PackageName].InstallVersion := Include.InstallVersion
                    Packages[Include.PackageName].Main := Include.Main
                } else
                    Packages[Include.PackageName] := Include
            }
        } else {
            Loop files path "*.ah*" {
                for Include in ReadIncludesFromFile(A_LoopFileFullPath)
                    Packages[Include.PackageName] := Include
            }
        }
    }
    return Packages
}

ReadIncludesFromFile(path) {
    Packages := []
    if !FileExist(path)
        return Packages
    Loop parse FileRead(path), "`n", "`r" {
        if !(A_LoopField ~= "^\s*#include")
            continue
        if !RegExMatch(A_LoopField, ".+_.+_.+")
            continue

        Packages.Push(InstallInfoToPackageInfo(A_LoopField))
    }
    return Packages
}

CleanPackages() {
    InstalledMap := Map(), Dependencies := Map()
    for PackageName, PackageInfo in g_InstalledPackages {
        InstalledMap[PackageInfo.InstallName] := PackageInfo
        InstalledMap[PackageInfo.PackageName] := PackageInfo
    }

    if FileExist("package.json") {
        for Dependency, Version in g_PackageJson["dependencies"] {
            if InstalledMap.Has(Dependency)
                Dependencies[Dependency] := Version
        }
        g_PackageJson["dependencies"] := Dependencies
        FileOpen("package.json", "w").Write(JSON.Dump(g_PackageJson, true))
    }

    Loop files ".\" g_LibDir, "D" {
        if RegExMatch(A_LoopFileName, "^.+_.+_.+$") && !InstalledMap.Has(A_LoopFileName)
            DirDelete(A_LoopFileFullPath, true)
    }

    if !FileExist(".\" g_LibDir "\packages.ahk")
        return

    NewContent := FileRead(".\" g_LibDir "\packages.ahk")
    Loop parse NewContent, "`n", "`r" {
        if !(A_LoopField ~= "^\s*#include")
            continue

        Found := false
        for PackageName, PackageInfo in g_InstalledPackages
            if InStr(A_LoopField, PackageInfo.InstallName) {
                Found := true
                break
            }
        if !Found
            StrReplace(NewContent, A_LoopField "`n")
    }
    FileOpen(".\" g_LibDir "\packages.ahk", "w").Write(NewContent)
}

FindLibDir(path := ".\") {
    path := RTrim(path, "\") "\"
    if DirExist(path "lib")
        return "lib"
    else if DirExist(path "includes")
        return "includes"
    return "lib"
}

IsGithubMinimalInstallPossible(PackageInfo, IgnoreVersion := false) {
    if !IgnoreVersion && !IsVersionSha(PackageInfo.Version)
        return false
    if !PackageInfo.Files.Length {
        return !!PackageInfo.Main
    }
    if PackageInfo.Files.Length = 1 {
        if PackageInfo.Files[1] ~= "(?<!\*)\.ahk?\d?$"
            return true
    } 
    for FileName in PackageInfo.Files {
        FileName := StrReplace(FileName, "/", "\")
        SplitPath(FileName,,, &Ext:="", &NameNoExt:="")
        if Ext = "" || Ext = "*" || NameNoExt = "" || NameNoExt = "*"
            return false
    }
    return true
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

GetVersionRangeCompareFunc(Range) {
    Range := StrLower(Range), OtherRange := ""
    Split := StrSplit(Range := Trim(Range), " ",, 2)
    if Split.Length > 1 {
        OtherRange := Split[2], Range := Split[1]
    }
    if Range = "*"
        Range := "latest"
    if Range && Range != "latest" {
        Plain := RegExReplace(Range, "[^\w-.]")
        if SubStr(Plain, 1, 1) = "v"
            Plain := SubStr(Plain, 2)
        if IsVersionSha(Plain) || IsVersionMD5(Plain)
            return (v) => v == Plain

        split := StrSplit(Plain, ".")
        if split.Length = 3 && split[3] = "x"
            split[3] := "0", Range := "~" Range, Plain := StrReplace(Plain, ".x", ".0")
        if split.Length = 2 && split[2] = "x"
            split[2] := "0", Range := "^" Range, Plain := StrReplace(Plain, ".x", ".0")
        CropLength := RegExReplace.Bind(,"^([~^><=]*\d{10,10})\d+", "$1")
        Plain := CropLength(Plain), Range := CropLength(Range)
        switch SubStr(Range, 1, 1) {
            case "~": ; Only accept patch versions
                CompareFunc := (v) => (v:=CropLength(v), VerCompare(v, ">=" Plain) && VerCompare(v, (split.Length > 1) ? "<" split[1] "." (Integer(split[2])+1) : "=" split[1]))
            case "^": ; Only accept minor and patch versions
                CompareFunc := (v) => (v:=CropLength(v), VerCompare(v, ">=" Plain) && VerCompare(v, "<" (Integer(split[1])+1)))
            case ">", "<":
                CompareFunc := (v) => VerCompare(CropLength(v), Range)
            default:
                CompareFunc := (v) => VerCompare(CropLength(v), "=" Plain)
        }
    } else
        CompareFunc := (v) => true
    if OtherRange
        return (v) => CompareFunc(v) && GetVersionRangeCompareFunc(OtherRange)
    return CompareFunc
}

IsVersionSha(version) => StrLen(version) = 7 && RegExMatch(version, "^\w+$")
IsVersionMD5(version) => StrLen(version) = 12 && RegExMatch(version, "^\w{12}$")
IsSemVer(input) => RegExMatch(input, "^[><=^~]*v?(?:((0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?)|\d+|\d+\.\d+|latest|\*)$")
IsVersionCompatible(version, range) => GetVersionRangeCompareFunc(range).Call(version)

MergeJsonInfoToPackageInfo(JsonInfo, PackageInfo) {
    if !PackageInfo.Dependencies.Count && JsonInfo.Has("dependencies")
        PackageInfo.Dependencies := JsonInfo["dependencies"]
    if !PackageInfo.Repository {
        PackageInfo.Repository := JsonInfo["repository"]["url"], PackageInfo.RepositoryType := JsonInfo["repository"]["type"]
        ParseRepositoryData(PackageInfo)
    }
    if !PackageInfo.Files.Length && JsonInfo.Has("files")
        PackageInfo.Files := JsonInfo["files"]
    if !PackageInfo.Main && JsonInfo.Has("main")
        PackageInfo.Main := JsonInfo["main"]
    return PackageInfo
}

ParsePackageName(PackageName) {
    PackageInfo := PackageInfoBase()
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

QueryForumsReleases(PackageInfo) {
    CdxJson := JSON.Load(DownloadURL("https://web.archive.org/cdx/search/cdx?url=autohotkey.com%2Fboards%2Fviewtopic.php&matchType=prefix&output=json&filter=statuscode:200&filter=urlkey:.*t=" PackageInfo.ThreadId))
    if CdxJson.Length < 2
        return []
    CdxJson.RemoveAt(1)
    Matches := []
    for Entry in CdxJson {
        if PackageInfo.Start
            if !(RegExMatch(Entry[3], "start=(\d+)", &match:="") && match[1] = PackageInfo.Start)
                continue
        ; Although the following could perhaps get extra matches from Wayback, it's more useful to
        ; use the post id to extract a specific post from a thread page.
        /*
        if PackageInfo.Post
            if !(RegExMatch(Entry[3], "p=(\d+)", &match:="") && match[1] = PackageInfo.Post)
                continue
        */
        if !PackageInfo.Start && InStr(Entry[3], "start=")
            continue
        Matches.Push({Repository:Entry[3], Version:Entry[2]})
    }
    return Matches
}

LoadPackageJson(path:=".\", &RawContent:="") {
    if FileExist("package.json") {
        PackageJson := LoadJson(RTrim(path, "\") "\package.json", &RawContent)
        if !PackageJson.Has("dependencies")
            PackageJson["dependencies"] := Map()
    } else {
        PackageJson := Map("dependencies", Map())       
    }
    PackageJson.Default := ""
    StandardizeRepositoryInfo(PackageJson)
    return PackageJson
}
LoadJson(fileName, &RawContent:="") => JSON.Load(RawContent := FileRead(fileName))

StandardizeRepositoryInfo(Info) {
    if !Info.Has("repository")
        return
    if IsObject(Info["repository"]) {
        if !Info["repository"].Has("type") && Info["repository"].Has("url")
            Info["repository"] := Info["repository"]["url"]
        else
            return
    }
    Info["repository"] := ExtractInfoFromRepositoryEntry(Info["repository"])
}

ExtractInfoFromRepositoryEntry(repo) {
    if loc := InStr(repo, "@",,-1)
        repo := SubStr(repo, 1, loc-1)
    repo := Trim(repo, "/\")
    
    if !repo
        return Map("type", "github", "url", "")
    if repo ~= "(\.zip|\.tar\.gz|\.tar|\.7z)$"
        repo := Map("type", "archive", "url", repo)
    else if InStr(repo, "github.com")
        repo := Map("type", "github", "url", RegExReplace(repo, ".*github\.com\/"))
    else if InStr(repo, "autohotkey.com")
        repo := Map("type", "forums", "url", repo)
    else if repo ~= "^(forums:)"
        repo := Map("type", "forums", "url", StrSplit(repo, ":",,2)[2])
    else if repo ~= "^(http|ftp):"
        repo := Map("type", "archive", "url", repo)
    else if repo ~= "^(github|gh):"
        repo := Map("type", "github", "url", StrSplit(repo, ":",,2)[2])
    else if repo ~= "^(gist:)"
        repo := Map("type", "gist", "url", StrSplit(repo, ":",,2)[2])
    else {
        repo := Map("type", "github", "url", repo)
    }
    return repo
}

WriteStdOut(msg) => FileAppend(msg "`n", "*")