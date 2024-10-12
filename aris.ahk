/*
    ARIS: AutoHotkey Repository Install System

    Requirements that Aris must fulfill and situations it must handle:
    1) Installing a library should either install it in the local Lib folder, or the Lib folder in My Documents\AutoHotkey for global installs.
    2) Installation creates a packages.ahk file, which also acts as a lock file describing the exact dependencies needed.
    3) Installation creates a package.json file to describe the range of dependencies allowed. This should
        be done automatically without needing user input, as most users simply want to use a library, not enter info
        about their own project.
    4) If an installed library has package.json, then its dependencies should also be installed in the main Lib folder
    5) A package is considered "installed" if it has an entry in package.json dependencies, packages.ahk #include,
        and it has an install folder in Lib folder
    6) "aris install" should query for package.json, packages.ahk, and search all project main folder and lib folder .ahk files for matching
        ARIS version style "Aris/Author/Name".
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

#include <Aris/packages>
#include <ui-main>
#include <utils>
#include <version>
#include <hash>
#include <web>

global g_GitHubRawBase := "https://raw.githubusercontent.com/Descolada/ARIS/main/"
global g_Index, g_Config := Map(), g_PackageJson, g_LocalLibDir := A_WorkingDir "\Lib\Aris", g_GlobalLibDir := A_MyDocuments "\AutoHotkey\Lib\Aris", g_InstalledPackages, g_GlobalInstalledPackages
global g_Switches := Mapi("local_install", false, "global_install", false, "force", false), g_CacheDir := A_ScriptDir "\cache"
global g_CommandAliases := Mapi("install", "install", "i", "install", "remove", "remove", "r", "remove", "rm", "remove", "uninstall", "remove", "update", "update", "update-index", "update-index", "list", "list", "clean", "clean")
global g_SwitchAliases := Mapi("--global", "global_install", "--global-install", "global_install", "-g", "global_install", "--local", "local_install", "--local-install", "local_install", "-l", "local_install", "-f", "force", "--force", "force", "--main", "main", "-m", "main", "--files", "files", "--alias", "alias", "as", "alias")
global g_MainGui := Gui("+MinSize640x400 +Resize", "Aris")
global g_AddedIncludesString := ""
global g_IsComSpecAvailable := false
A_FileEncoding := "UTF-8"

if !A_Args.Length && !DllCall("GetStdHandle", "int", -11, "ptr") { ; Hack to detect whether we were run from Explorer
    try {
        ; For some reason this fixes the tray menu icon. Without A_ComSpec it doesn't work.
        Run A_ComSpec ' /c ""' A_AhkPath '" "' A_ScriptFullPath '" --working-dir "' A_WorkingDir '""',, "Hide"
        ExitApp
    }
}

try g_IsComSpecAvailable := !RunWait(A_ComSpec " /c echo 1",, "Hide")

Console := DllCall("AttachConsole", "UInt", 0x0ffffffff, "ptr")

OnError(WriteErrorStdOut)

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

if !g_Config.Has("auto_update_index_daily") || (g_Config["auto_update_index_daily"] && (Abs(DateDiff(A_NowUTC, g_Config["auto_update_index_daily"], "Days")) >= 1)) {
    UpdatePackageIndex()
}

Loop files A_ScriptDir "\*.*", "D" {
    if A_LoopFileName ~= "^~temp-\d+"
        DirDelete(A_LoopFileFullPath, true)
}

ClearCache()

if !g_Config.Has("first_run") || g_Config["first_run"] {
    try AddArisToPATH()
    catch
        WriteStdOut "Failed to add Aris to PATH (missing rights to write to registry?)"
    try AddArisShellMenuItem()
    catch
        WriteStdOut "Failed to add Aris shell menu item (missing rights to write to registry?)"
    g_Config["first_run"] := false
    FileOpen("assets/config.json", "w").Write(JSON.Dump(g_Config, true))
}


if (!A_Args.Length || (A_Args.Length = 1 && FileExist(A_Args[1]) && A_Args[1] ~= "i)\.ahk?\d?$")) {
    Persistent()
    LaunchGui(A_Args.Length ? A_Args[1] : unset)
} else {
    Command := "", Targets := [], Files := [], LastSwitch := "", Switches := Mapi("main", "", "files", [], "alias", "")
    for i, Arg in A_Args {
        if LastSwitch = "main" {
            LastSwitch := "", Switches["main"] := StrReplace(Arg, "\", "/")
            continue
        } else if LastSwitch = "alias" {
            LastSwitch := "", Switches["alias"] := Arg
            continue
        }
        if g_CommandAliases.Has(Arg)
            Command := g_CommandAliases[Arg]
        else if g_SwitchAliases.Has(Arg) {
            if g_SwitchAliases[Arg] = "main" || g_SwitchAliases[Arg] = "files" || g_SwitchAliases[Arg] = "alias" {
                LastSwitch := g_SwitchAliases[Arg]
                continue
            }
            g_Switches[g_SwitchAliases[Arg]] := true
        } else if !Command && !LastSwitch
            WriteStdOut("Unknown command. Use install, remove, update, or list."), ExitApp()
        else {
            if LastSwitch = "files" {
                Switches["files"].Push(StrReplace(Arg, "\", "/"))
                continue
            }
            Targets.Push(Arg)
        }
        LastSwitch := ""
    }
    switch Command, 0 {
        case "install":
            if Targets.Length {
                for target in Targets {
                    if target ~= "i)\.ahk?\d?$" && FileExist(target)
                        InstallPackageDependencies(target)
                    else
                        InstallPackage(target,, Switches)
                }
            } else {
                InstallPackageDependencies()
            }
            OutputAddedIncludesString(, !Targets.Length)
        case "remove":
            if Targets.Length {
                for target in Targets
                    RemovePackage(target)
            } else
                WriteStdOut("Specify a package to remove.")
        case "update":
            if !FileExist(A_WorkingDir "\package.json") {
                WriteStdOut "Missing package.json, cannot update package!"
                WriteStdOut '`tInformation: Use "aris install" if you want to install missing dependecies from the projects scripts.'
                ExitApp
            }
            if Targets.Length {
                for target in Targets
                    InstallPackage(target, 1)
            } else {
                UpdateWorkingDirPackage()
            }
            OutputAddedIncludesString(1, !Targets.Length)
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
    if DirExist(g_CacheDir) {
        if Force {
            DirDelete(g_CacheDir, true)
            DirCreate(g_CacheDir)
        } else {
            loop files g_CacheDir "\*.*", "F" {
                AccessTime := FileGetTime(A_LoopFileFullPath, "A")
                if DateDiff(A_Now, AccessTime, "Days") > 30
                    FileDelete(A_LoopFileFullPath)
            }
        }
    } else
        DirCreate(g_CacheDir)
}

AddArisToPATH() {
    ; Get the current PATH in this roundabout way because of the Store version registry virtualization
    CurrPath := g_IsComSpecAvailable ? RunCMD(A_ComSpec . " /c " 'reg query HKCU\Environment /v PATH') : RegRead("HKCU\Environment", "PATH")
    CurrPath := RegExReplace(CurrPath, "^[\w\W]*?PATH\s+REG_SZ\s+",,,1)
    Global G_RunCMD
    if g_IsComSpecAvailable && G_RunCMD.ExitCode
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
        g_IsComSpecAvailable ? RunWait(A_ComSpec ' /c SETX PATH "' CurrPath ';' LocalAppData '\Programs\Aris"',, "Hide") : RegWrite(CurrPath ';' LocalAppData '\Programs\Aris', "REG_SZ", "HKCU\Environment", "PATH")
        SendMessage(0x1A, 0, StrPtr("Environment"), 0xFFFF)
    }
}

RemoveArisFromPATH() {
    if !(LocalAppData := EnvGet("LOCALAPPDATA"))
        return

    CurrPath := g_IsComSpecAvailable ? RunCMD(A_ComSpec . " /c " 'reg query HKCU\Environment /v PATH') : RegRead("HKCU\Environment", "PATH")
    CurrPath := RegExReplace(CurrPath, "^[\w\W]*?PATH\s+REG_SZ\s+",,,1)

    Global G_RunCMD
    if g_IsComSpecAvailable && G_RunCMD.ExitCode
        return

    if InStr(CurrPath, ";" LocalAppData "\Programs\Aris") {
        g_IsComSpecAvailable ? RunWait(A_ComSpec ' /c SETX PATH "' StrReplace(CurrPath, ";" LocalAppData "\Programs\Aris") '"',, "Hide") : RegWrite(StrReplace(CurrPath, ";" LocalAppData "\Programs\Aris"), "REG_SZ", "HKCU\Environment", "PATH")
        SendMessage(0x1A, 0, StrPtr("Environment"), 0xFFFF)
    }
    if FileExist(LocalAppData "\Programs\Aris\Aris.bat") {
        DirDelete(LocalAppData "\Programs\Aris", true)
    }
}

IsArisInPATH() {
    if !(LocalAppData := EnvGet("LOCALAPPDATA"))
        return false
    CurrPath := g_IsComSpecAvailable ? RunCMD(A_ComSpec . " /c " 'reg query HKCU\Environment /v PATH') : RegRead("HKCU\Environment", "PATH", "")
    CurrPath := RegExReplace(CurrPath, "^[\w\W]*?PATH\s+REG_SZ\s+",,,1)
    if CurrPath && InStr(CurrPath, LocalAppData "\Programs\Aris")
        return true
    return false
}

AddArisShellMenuItem() {
    BaseKey := GetArisShellRegistryKey()
    if g_IsComSpecAvailable {
        RunCMD(A_ComSpec . " /c reg add " BaseKey '\Shell\Aris /t REG_SZ /d "Install Aris packages" /f')
        RunCMD(A_ComSpec . " /c reg add " BaseKey '\Shell\Aris\command /t REG_SZ /d "\"' A_AhkPath '\" \"' A_ScriptFullPath '\" \"%1\"" /f')
    } else {
        RegWrite("Install Aris packages", "REG_SZ", BaseKey '\Shell\Aris')
        RegWrite('"' A_AhkPath '" "' A_ScriptFullPath '" "%1"', "REG_SZ", BaseKey '\Shell\Aris\command')
    }
}

RemoveArisShellMenuItem() {
    BaseKey := GetArisShellRegistryKey()
    g_IsComSpecAvailable ? RunCMD(A_ComSpec . " /c reg delete " BaseKey '\Shell\Aris /f') : RegDeleteKey(BaseKey '\Shell\Aris')
}

IsArisShellMenuItemPresent() {
    try {
        RegRead(GetArisShellRegistryKey() "\Shell\Aris\command")
        return 1
    }
    return 0
}

GetArisShellRegistryKey() {
    BaseKey := "HKCU\SOFTWARE\Classes\AutoHotkeyScript"
    try {
        RegRead(BaseKey '\Shell\Aris\command')
        return BaseKey
    }

    ; Check for Store Edition
    Loop Reg "HKCU\SOFTWARE\Classes\.ahk\OpenWithProgids", "V"
        KeyName := A_LoopRegName
    if IsSet(KeyName)
        return "HKCU\SOFTWARE\Classes\" KeyName
    
    return "HKCU\SOFTWARE\Classes\AutoHotkeyScript"
}

RefreshGlobals() {
    LoadPackageIndex()
    LoadConfig()
    LoadGlobalInstalledPackages()
    RefreshWorkingDirGlobals()
}

RefreshWorkingDirGlobals() {
    global g_PackageJson := LoadPackageJson()
    global g_InstalledPackages := QueryInstalledPackages()
    global g_LocalLibDir := A_WorkingDir "\Lib\Aris"
}

LoadGlobalInstalledPackages() {
    global g_GlobalInstalledPackages := Mapi(), GlobalInstalledPackages := Map()
    if FileExist(g_GlobalLibDir "\global-dependencies.json") {
        GlobalInstalledPackages := JSON.Load(FileRead(g_GlobalLibDir "\global-dependencies.json"))
    }
    for PackageName, Info in GlobalInstalledPackages {
        NewInfo := Mapi()
        for InstallDir, Projects in Info
            NewInfo[InstallDir] := Projects
        g_GlobalInstalledPackages[PackageName] := NewInfo
    }
}

SaveGlobalInstalledPackages() {
    DirCreateEx(g_GlobalLibDir)
    if Content := JSON.Dump(g_GlobalInstalledPackages, true) {
        FileOpen(g_GlobalLibDir "\global-dependencies.json", "w").Write(Content)
    }
}

; InstallType: 0 = install, 1 := update
; PackageType: 0 = regular, 1 = dependency
OutputAddedIncludesString(InstallType:=0, PackageType:=0) {
    global g_AddedIncludesString
    if !g_AddedIncludesString {
        WriteStdOut "No new packages installed"
        return
    }
    Plural := InStr(g_AddedIncludesString := Trim(g_AddedIncludesString), "`n")
    WriteStdOut (InstallType = 0 ? "Installed" : "Updated") " " (PackageType = 0 ? "package" (Plural ? "s" : "") : "dependenc" (Plural ? "ies" : "y")) " include directive" (Plural ? "s" : "") ":"
    WriteStdOut g_AddedIncludesString
    g_AddedIncludesString := ""
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
        this.Author := Author, this.Name := RemoveAhkSuffix(Name), this.Version:=Version
        if Author && Name
            this.PackageName := Author "/" Name
    }
    Author := "", Name := "", PackageName := "", Version := "", BuildMetadata := "", Repository := "", 
    RepositoryType := "", Main := "", Dependencies := Map(), DependencyEntry := "", InstallEntry := "", Files := [],
    Branch := "", ThreadId := "", InstallVersion := "", DependencyVersion := "", IsMain := false, Global := false
}

InputToPackageInfo(Input, Skip:=0, Switches?) {
    static DefaultSwitches := Mapi("main", "", "files", [], "alias", "")
    if !IsSet(Switches)
        Switches := DefaultSwitches
    else {
        for k, v in DefaultSwitches
            if !Switches.Has(k)
                Switches[k] := v
    }
    if InStr(Input, " -") {
        argv := DllCall("shell32.dll\CommandLineToArgv", "str", Input, "int*", &numArgs:=0, "ptr")
        InstallCommand := StrGet(NumGet(argv, "ptr"),,"UTF-16")
        local LastSwitch := ""
        Loop numArgs {
            if A_Index = 1
                continue
            local Arg := StrGet(NumGet(argv+(A_Index-1)*A_PtrSize, "ptr"),,"UTF-16")
            if LastSwitch = "main" {
                LastSwitch := "", Switches["main"] := StrReplace(Arg, "\", "/")
                continue
            } else if LastSwitch = "alias" {
                LastSwitch := "", Switches["alias"] := Arg
                continue
            }
            if g_SwitchAliases.Has(Arg) {
                if g_SwitchAliases[Arg] = "main" || g_SwitchAliases[Arg] = "files" {
                    LastSwitch := g_SwitchAliases[Arg]
                    continue
                }
            } else if !LastSwitch {
                if IsSemVer(Arg)
                    InstallCommand .= " " Arg
                else
                    throw Error("Unknown command when reading input", -1, Arg)
            } else {
                if LastSwitch = "files" {
                    Arg := StrReplace(Arg, "\", "/")
                    for f in Switches["files"]
                        if f = Arg
                            continue 2
                    Switches["files"].Push(Arg)
                    continue
                }
            }
            LastSwitch := ""
        }
        PackageInfo := InputToPackageInfo(InstallCommand, Skip)
    } else {
        PackageInfo := PackageInfoBase()
    
        if loc := InStr(Input, "@",,-1) {
            PackageInfo.Version := SubStr(Input, loc+1)
            Input := SubStr(Input, 1, loc-1)
            if loc := InStr(PackageInfo.Version, "+",,-1)
                PackageInfo.BuildMetadata := SubStr(PackageInfo.Version, loc+1), PackageInfo.Version := SubStr(PackageInfo.Version, 1, loc-1)
        }
        Input := Trim(Input, "/\")
        
        if !Input
            throw Error("Couldn't find a target package", -1, Input)

        PackageInfo.Repository := Input
        ParseRepositoryData(PackageInfo)
    }

    if !PackageInfo.RepositoryType {
        FoundPackageInfo := SearchPackageByName(Input, Skip)
        FoundPackageInfo.Version := PackageInfo.Version || FoundPackageInfo.Version || PackageInfo.InstallVersion || FoundPackageInfo.InstallVersion, FoundPackageInfo.BuildMetadata := PackageInfo.BuildMetadata || FoundPackageInfo.BuildMetadata
        PackageInfo := FoundPackageInfo
    }

    if Switches["files"].Length
        PackageInfo.Files := Switches["files"]

    if Switches["main"] != "" {
        PackageInfo.Main := Switches["main"]
        if !g_Index.Has(PackageInfo.PackageName) && !PackageInfo.Name {
            PackageInfo.Name := RemoveAhkSuffix(StrSplit(Switches["main"], "/")[-1])
            PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name
        }
    }

    if Switches["alias"] != "" {
        Split := StrSplit(Switches["alias"], "/",,2)
        if Split.Length = 1
            PackageInfo.Name := Split[1], PackageInfo.PackageName := (PackageInfo.PackageName ? StrSplit(PackageInfo.PackageName, "/")[1] "/" PackageInfo.Name : "")
        else
            PackageInfo.Author := Split[1], PackageInfo.Name := Split[2], PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name
    }

    StandardizePackageInfo(PackageInfo)

    return PackageInfo
}

StandardizePackageInfo(PackageInfo) {
    local i
    PackageInfo.Main := Trim(StrReplace(PackageInfo.Main, "\", "/"), "/ ")
    if PackageInfo.Main && !(PackageInfo.Main ~= "i)\.ahk?\d?$")
        PackageInfo.Main .= ".ahk"
    for i, PackageFile in PackageInfo.Files {
        PackageInfo.Files[i] := Trim(StrReplace(PackageFile, "\", "/"), "/ ")
    }
    MergeMainFileToFiles(PackageInfo, PackageInfo.Main)
    if !PackageInfo.PackageName
        PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name
    PackageInfo.Global := PackageInfo.Global || g_Switches["global_install"]
    return PackageInfo
}

InstallInfoToPackageInfo(PackageName, Version := "", Main := "", InstallEntry:="") {
    PackageName := StrReplace(PackageName, "\", "/")
    SplitName := StrSplit(PackageName, "/")
    StrReplace(PackageName, "/",,, &Count:=0)
    if Count != 1
        throw Error("Invalid package name", -1, PackageName)

    if !InstallEntry {
        PackageInfo := InputToPackageInfo(PackageName (Version ? "@" Version : ""), 1)
    } else {
        PackageInfo := InputToPackageInfo(InstallEntry, 1)
    }

    PackageInfo.Name := SplitName[2], PackageInfo.Author := SplitName[1], PackageInfo.PackageName := PackageName

    PackageInfo.InstallEntry := InstallEntry
    if Main
        PackageInfo.Main := Main
    if Version
        PackageInfo.InstallVersion := Version

    PackageInfo.InstallName := PackageInfo.PackageName "@" PackageInfo.Version

    if g_PackageJson["dependencies"].Has(PackageInfo.PackageName) {
        PackageInfo.DependencyEntry := DependencyEntry := g_PackageJson["dependencies"][PackageInfo.PackageName]
        if IsSemVer(DependencyEntry) || IsVersionSha(DependencyEntry) || IsVersionMD5(DependencyEntry) {
            PackageInfo.DependencyVersion := DependencyEntry
        } else if loc := InStr(DependencyEntry, "@",,-1) {
                PackageInfo.DependencyVersion := RegExReplace(SubStr(DependencyEntry, loc+1), " (-m|--main|--files).*$")
                DependencyEntry := SubStr(DependencyEntry, 1, loc-1)
                if loc := InStr(PackageInfo.DependencyVersion, "+",,-1)
                    PackageInfo.DependencyBuildMetadata := SubStr(PackageInfo.DependencyVersion, loc+1), PackageInfo.DependencyVersion := SubStr(PackageInfo.DependencyVersion, 1, loc-1)
        } else
            PackageInfo.DependencyVersion := "*"
    } else 
        PackageInfo.DependencyVersion := PackageInfo.InstallVersion

    if !PackageInfo.RepositoryType
        PackageInfo.RepositoryType := "github"
    if !PackageInfo.Repository
        PackageInfo.Repository := PackageInfo.PackageName

    ParseRepositoryData(PackageInfo)

    StandardizePackageInfo(PackageInfo)
    return PackageInfo        
}

DependencyEntryToPackageInfo(PackageName, DependencyEntry) {
    if IsSemVer(DependencyEntry) || IsVersionSha(DependencyEntry) || IsVersionMD5(DependencyEntry) {
        try {
            PackageInfo := SearchPackageByName(PackageName, 1)
        } catch {
            PackageInfo := PackageInfoBase()
        }
        PackageInfo.DependencyVersion := DependencyEntry
    } else if InStr(DependencyEntry, ":") || InStr(DependencyEntry, "/") {
        PackageInfo := InputToPackageInfo(DependencyEntry)
        PackageInfo.DependencyVersion := PackageInfo.Version, PackageInfo.Version := ""
    } else
        throw Error("Invalid dependency entry", -1, PackageName ":" DependencyEntry)
    PackageInfo.DependencyEntry := DependencyEntry
    PackageInfo.PackageName := PackageName
    Split := StrSplit(PackageName, "/",, 2)
    PackageInfo.Author := Split[1]
    PackageInfo.Name := RemoveAhkSuffix(Split[2])
    StandardizePackageInfo(PackageInfo)
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
        for Name, Info in g_InstalledPackages {
            if Name ~= "i)\/\Q" InputName "\E$"
                found.Push(Info)
        }
        if !found.Length && Skip != 1 {
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
            found[1] := found[1].Clone(), MergeJsonInfoToPackageInfo(g_Index[found[1].PackageName], found[1])
        return found[1]
    } else if Skip != 1 {
        for Name, Info in QueryPackageDependencies() {
            if Name = InputAuthor "/" InputName {
                if g_Index.Has(Info.PackageName)
                    Info := Info.Clone(), MergeJsonInfoToPackageInfo(g_Index[Info.PackageName], Info)
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
    PackageInfo.PackageName := RemoveAhkSuffix(PackageInfo.PackageName)
    return PackageInfo
}

ParseRepositoryData(PackageInfo) {
    Input := PackageInfo.Repository
    if !PackageInfo.RepositoryType {
        if Input ~= "i)(\.zip|\.tar\.gz|\.tar|\.7z)$" {
            PackageInfo.RepositoryType := "archive"
        } else if InStr(Input, "gist.github.com") || Input ~= "i)^(gist:)" {
            PackageInfo.RepositoryType := "gist"
        } else if InStr(Input, "github.com") || Input ~= "i)^(github|gh):" {
            PackageInfo.RepositoryType := "github"
        } else if InStr(Input, "autohotkey.com") || Input ~= "i)^(forums:)" {
            PackageInfo.RepositoryType := "forums"
        } else {
            Split := StrSplit(Input, "/")
            if Split.Length > 3 {
                if Input ~= "i)\.ahk?\d?$"
                    PackageInfo.RepositoryType := "ahk"
                else
                    PackageInfo.RepositoryType := "archive", PackageInfo.Repository := Input
            } else 
                return
        }
    }

    switch PackageInfo.RepositoryType, 0 {
        case "archive":
            SplitSource := StrSplit(PackageInfo.Repository, "/")
            SplitPath(SplitSource[-1],,,, &NameNoExt:="")
            PackageInfo.Author := "Unknown", PackageInfo.Name := RemoveAhkSuffix(NameNoExt)
        case "ahk":
            PackageInfo.Author := PackageInfo.Author || "Unknown", PackageInfo.Name := RemoveAhkSuffix(PackageInfo.Name || StrSplit(PackageInfo.Repository, "/")[-1])
        case "github":
            PackageInfo.Repository := StrSplit(RegExReplace(Input, "i).*github\.com\/", ":",, 1), ":",, 2)[-1]
            Split := StrSplit(PackageInfo.Repository, "/")
            PackageInfo.Author := PackageInfo.Author || Split[1], PackageInfo.Name := RemoveAhkSuffix(PackageInfo.Name || Split[2]), PackageInfo.Branch := Split.Length = 3 ? Split[3] : ""
        case "forums":
            if !RegExMatch(Input, "i)t=(\d+).*?((?<=code=|codebox=)\d+)?$", &match:="")
                throw Error("Detected AutoHotkey forums link, but couldn't find thread id", -1, Input)
            PackageInfo.ThreadId := match[1], PackageInfo.CodeBox := (match.Count = 2 && match[2] ? Integer(match[2]) : 1)
            PackageInfo.Start := RegExMatch(Input, "i)&start=(\d+)", &match:="") ? match[1] : ""
            PackageInfo.Post := RegExMatch(Input, "i)&p=(\d+)", &match:="") ? match[1] : ""
            if PackageInfo.Version = "latest" || PackageInfo.BuildMetadata
                PackageInfo.Repository := "https://www.autohotkey.com/boards/viewtopic.php?t=" PackageInfo.ThreadId (PackageInfo.Start ? "&start=" PackageInfo.Start : "") (PackageInfo.Post ? "&p=" PackageInfo.Post : "") "&codenum=" PackageInfo.CodeBox
            if RegExMatch(PackageInfo.Version, "^([><=]*)(\d+)$", &match:="") && (len := StrLen(match[2])) != 14
                PackageInfo.Version := match[1] (Integer(match[2]) * 10**(14-len))
            ; Wayback Machine repo name is generated after finding a version match or latest version
        case "gist":
            PackageInfo.Repository := StrSplit(Input := RegExReplace(Input, "i).*github\.com\/[^\/]+/", ":",, 1), ":",,2)[-1]
            if InStr(Input, "/") {
                Split := StrSplit(PackageInfo.Repository, "/")
                PackageInfo.Repository := Split[1]
                PackageInfo.Main := Split[2]
                PackageInfo.Name := RemoveAhkSuffix(PackageInfo.Name || PackageInfo.Main)
            }
    }
}

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
    if repo ~= "i)(\.zip|\.tar\.gz|\.tar|\.7z)$"
        repo := Map("type", "archive", "url", repo)
    else if InStr(repo, "github.com")
        repo := Map("type", "github", "url", RegExReplace(repo, "i).*github\.com\/"))
    else if InStr(repo, "autohotkey.com")
        repo := Map("type", "forums", "url", repo)
    else if repo ~= "i)^(forums:)"
        repo := Map("type", "forums", "url", StrSplit(repo, ":",,2)[2])
    else if repo ~= "^(http|ftp|www\.):" {
        if repo ~= "i)\.ahk?\/d?$"
            repo := Map("type", "ahk", "url", repo)
        else
            repo := Map("type", "archive", "url", repo)
    } else if repo ~= "i)^(github|gh):"
        repo := Map("type", "github", "url", StrSplit(repo, ":",,2)[2])
    else if repo ~= "i)^(gist:)"
        repo := Map("type", "gist", "url", StrSplit(repo, ":",,2)[2])
    else {
        repo := Map("type", "github", "url", repo)
    }
    return repo
}

; Update=0 means install and skip if already installed
; Update=1 means allow update if package is already installed, but skip if is not installed
; Update=2 means allow update and install if not installed
InstallPackage(Package, Update:=0, Switches?) {
    global g_PackageJson, g_InstalledPackages, g_LocalLibDir, g_AddedIncludesString
    CurrentlyInstalled := Mapi()
    if !(Package is Object) {
        try PackageInfo := InputToPackageInfo(Package,, Switches?)
        catch as err {
            WriteStdOut err.Message (err.Extra ? ": " err.Extra : "")
            return
        }
    } else
        PackageInfo := Package
    if Update && !g_InstalledPackages.Has(PackageInfo.PackageName) && !PackageInfo.IsMain
        Update := 0
    ReadablePackageName := Trim(RemoveAhkSuffix(Package is Object ? Package.PackageName : PackageInfo.PackageName ? PackageInfo.PackageName : Package), "/")
    if !InStr(ReadablePackageName, "/")
        ReadablePackageName := (Package is Object) ? PackageInfo.RepositoryType ":" PackageInfo.Repository : Package
    WriteStdOut 'Starting ' (PackageInfo.Global ? "global " : "") (Update ? "update" : "install") ' of package "' ReadablePackageName '"'
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

    if Update && PackageInfo.DependencyVersion && (Package is Object ? !Package.Version : !InStr(Package, "@")) {
        PackageInfo.Version := PackageInfo.DependencyVersion
    }

    if PackageInfo.IsMain {
        g_Switches["global_install"] := false
        PrevWorkingDir := A_WorkingDir
        try {
            VerifyPackageIsDownloadable(PackageInfo)
            if IsPackageInstalled(PackageInfo, g_InstalledPackages, [TempDir, g_LocalLibDir, g_GlobalLibDir])
                goto Cleanup
            FinalDirName := DownloadSinglePackage(PackageInfo, TempDir, g_LocalLibDir)
            A_WorkingDir := TempDir "\" FinalDirName
            Dependencies := Map()
            LibDir := A_WorkingDir "\Lib\Aris"
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
    FinalDirName := StrReplace(DownloadResult.InstallName, "/", "\")

    if PackageInfo.IsMain {
        DirMove(TempDir "\" FinalDirName, A_WorkingDir, 2)
    } else {
        if DownloadResult.Global {
            if !DirExist(g_GlobalLibDir "\" FinalDirName)
                DirMove(TempDir, g_GlobalLibDir, 2)
            if !DirExist(g_LocalLibDir)
                DirCreateEx(g_LocalLibDir)
        } else
            DirMove(TempDir, g_LocalLibDir, 2)
    }

    PackageJson := LoadPackageJson()

    if FileExist(g_LocalLibDir "\packages.ahk")
        IncludeFileContent := FileRead(g_LocalLibDir "\packages.ahk")
    else
        IncludeFileContent := "; Avoid modifying this file manually`n`n"

    g_AddedIncludesString := ""
    for IncludePackageName, Include in g_InstalledPackages {
        if CurrentlyInstalled.Has(IncludePackageName "@" Include.InstallVersion)
            continue
        if g_Switches["global_install"] || Include.Global {
            if !g_GlobalInstalledPackages.Has(IncludePackageName)
                g_GlobalInstalledPackages[IncludePackageName] := Mapi()
            if !g_GlobalInstalledPackages[IncludePackageName].Has(DownloadResult.InstallName)
                g_GlobalInstalledPackages[IncludePackageName][DownloadResult.InstallName] := []
            g_GlobalInstalledPackages[IncludePackageName][DownloadResult.InstallName].Push(A_WorkingDir)
        }
        if Include.DependencyEntry { ; Package was already installed
            if !IsVersionCompatible(Include.InstallVersion, Include.DependencyVersion) {
                PackageJson["dependencies"][IncludePackageName] := ReplaceInstallCommandVersion(Include.DependencyEntry, Include.InstallVersion (Include.InstallBuildMetadata ? "+" Include.InstallBuildMetadata : ""))
            } else if !PackageJson["dependencies"].Has(IncludePackageName)
                PackageJson["dependencies"][IncludePackageName] := Include.DependencyEntry
        } else { ; Package was not installed
            SemVerVersion := IsSemVer(Include.InstallVersion) && !(Include.InstallVersion ~= "^[~^><=]") ? "^" Include.InstallVersion : Include.InstallVersion
            PackageJson["dependencies"][IncludePackageName] := g_Index.Has(Include.PackageName) ? SemVerVersion : ConstructInstallCommand(Include, SemVerVersion (Include.InstallBuildMetadata ? "+" Include.InstallBuildMetadata : ""))
        }
        if Update
            WriteStdOut 'Package successfully updated to "' IncludePackageName "@" Include.InstallVersion '".`n'
        else
            WriteStdOut 'Package "' IncludePackageName "@" Include.InstallVersion '" successfully installed.`n'

        if !Include.Main {
            if Include.Files.Length = 1
                Include.Main := StrSplitLast(Include.Files[1], "/")[-1]
        }

        if Include.Main {
            if !DirExist(g_LocalLibDir "\" Include.Author)
                DirCreate(g_LocalLibDir "\" Include.Author)
            FileOpen(g_LocalLibDir "\" Include.Author "\" Include.Name ".ahk", "w").Write("#include " (Include.Global ? "%A_MyDocuments%\AutoHotkey\Lib\Aris\" Include.Author "\" : ".\") StrSplit(Include.InstallName, "/",,2)[-1] "\" StrReplace(Include.Main, "/", "\"))
            InstallEntry := ConstructInstallCommand(Include, Include.InstallVersion (Include.BuildMetadata ? "+" Include.BuildMetadata : ""))
            Addition := (Include.Global ? "#include <Aris/" Include.PackageName ">" : "#include ./" Include.PackageName ".ahk") " `; " InstallEntry "`n"
            if !InStr(IncludeFileContent, Addition)
                IncludeFileContent .= Addition, g_AddedIncludesString .= "#include <Aris/" Include.PackageName "> `; " InstallEntry
        }
    }

    if !PackageJson["dependencies"].Count
        PackageJson.Delete("dependencies")

    if !PackageInfo.IsMain
        FileOpen("package.json", 0x1).Write(JSON.Dump(PackageJson, true))
    FileOpen(g_LocalLibDir "\packages.ahk", 0x1).Write(IncludeFileContent)
    g_PackageJson := LoadPackageJson()
    SaveGlobalInstalledPackages()

    Result := 1

    Cleanup:
    try DirDelete(TempDir, 1)
    return Result
}

InstallPackageDependencies(From := "") {
    Dependencies := QueryPackageDependencies(, From)
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
                WriteStdOut "Package successfully updated!`n"
        }
    }
}

UpdateWorkingDirPackage() {
    if !g_PackageJson.Has("name") || !g_PackageJson["name"] {
        WriteStdOut "Missing package name from metadata, cannot update package!"
        ExitApp
    }
    ThisPackage := ParsePackageName(g_PackageJson["name"])
    MergeJsonInfoToPackageInfo(g_PackageJson, ThisPackage)
    ThisPackage.IsMain := 1
    ThisPackage.Files := ["*.*"]
    Result := InstallPackage(ThisPackage, 1)
    if g_PackageJson["name"] = "Descolada/Aris" && Result {
        if !A_Args.Length {
            MsgBox "Aris successfully updated, press OK to restart"
            Run(A_AhkPath ' "' A_ScriptFullPath '"')
        } else {
            WriteStdOut "Aris successfully updated"
        }
        ExitApp
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
            Dependencies := QueryInstalledPackageDependencies(Match, InstalledPackages, g_LocalLibDir)
            if Dependencies.Length {
                DepString := 'Cannot remove package "' Match.PackageName "@" Match.InstallVersion '" as it is depended on by: '
                for Dependency in Dependencies
                    DepString .= "`n`t" Dependency.PackageName "@" Dependency.DependencyVersion

                WriteStdOut DepString
                return
            }
        }

        ForceRemovePackage(Match, Match.Global ? g_GlobalLibDir : g_LocalLibDir, RemoveDependencyEntry)
        WriteStdOut 'Package "' Match.PackageName "@" Match.InstallVersion '" removed!'
    } else {
        WriteStdOut "Multiple matches found:"
        for Match in Matches
            WriteStdOut "`t" Match.PackageName "@" Match.InstallVersion
    }
}

ForceRemovePackage(PackageInfo, LibDir, RemoveDependencyEntry:=true) {
    global g_PackageJson
    if RemovePackageFromGlobalInstallEntries(PackageInfo) {
        if DirExist(LibDir "\" PackageInfo.InstallName)
            DirDelete(LibDir "\" PackageInfo.InstallName, true)
    }
    if FileExist(g_LocalLibDir "\" PackageInfo.PackageName ".ahk")
        FileDelete(g_LocalLibDir "\" PackageInfo.PackageName ".ahk")
    try DirDelete(LibDir "\" PackageInfo.Author)
    if LibDir != g_LocalLibDir
        try DirDelete(g_LocalLibDir "\" PackageInfo.Author)
    if FileExist(g_LocalLibDir "\packages.ahk") {
        OldPackages := FileRead(g_LocalLibDir "\packages.ahk")
        NewPackages := RegExReplace(OldPackages, "i)#include (<Aris|\.|%A_MyDocuments%)\/\Q" PackageInfo.PackageName "\E(>|\.ahk)( `; .*|$)\n\r?",,, 1)
        if OldPackages != NewPackages
            FileOpen(g_LocalLibDir "\packages.ahk", "w").Write(NewPackages)
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
}

ForceRemovePackageWithDependencies(PackageInfo, InstalledPackages, LibDir, RemoveDependencyEntry:=true) {
    ForceRemovePackage(PackageInfo, LibDir, RemoveDependencyEntry)
    Dependencies := QueryInstalledPackageDependencies(PackageInfo, InstalledPackages, LibDir)
    for Dependency, Version in Dependencies {
        DependencyInfo := DependencyEntryToPackageInfo(Dependency, Version)
        ForceRemovePackage(DependencyInfo, LibDir, RemoveDependencyEntry)
        for i, InstalledPackage in InstalledPackages {
            if (InstalledPackage.PackageName = DependencyInfo.PackageName && InstalledPackage.Version = DependencyInfo.Version) {
                InstalledPackage.RemoveAt(i)
                RemovePackageFromGlobalInstallEntries(InstalledPackage)
                break
            }
        }
        ForceRemovePackageWithDependencies(DependencyInfo, InstalledPackages, LibDir, RemoveDependencyEntry)
    }
}

ConstructInstallCommand(PackageInfo, Version) {
    if g_Index.Has(PackageInfo.PackageName) {
        return PackageInfo.PackageName "@" Version
    }

    vargs := ""
    switch PackageInfo.RepositoryType, 0 {
        case "gist":
            vargs := "gist:" PackageInfo.Repository "/" PackageInfo.Main "@" Version
        case "forums":
            vargs := "forums:t=" PackageInfo.ThreadId (PackageInfo.Start ? "&start=" PackageInfo.Start : "") (PackageInfo.Post ? "&p=" PackageInfo.Post : "") "&codebox=" PackageInfo.CodeBox "@" Version
        case "github":
            vargs := "github:" PackageInfo.Repository "@" Version
        default:
            vargs := PackageInfo.Repository "@" Version
    }

    if PackageInfo.Main && !(PackageInfo.Files.Length = 1 && StrSplitLast(PackageInfo.Files[1], "/")[-1] = StrSplitLast(PackageInfo.Main, "/")[-1])
        vargs .= " --main " QuoteFile(PackageInfo.Main)
    if PackageInfo.Files.Length && !(PackageInfo.Files.Length = 1 && PackageInfo.Files[1] = "*.*") {
        vargs .= " --files"
        for PackageFile in PackageInfo.Files
            vargs .= " " QuoteFile(PackageFile)
    }
    return vargs

    /*
    PackageInfo.DependencyEntry := "gist:" PackageInfo.Repository "/" PackageInfo.Main "@" ((IsVersionSha(PackageInfo.DependencyVersion) ? "" : PackageInfo.DependencyVersion) || PackageInfo.Version || PackageInfo.InstallVersion)

    PackageInfo.DependencyEntry := "forums:t=" PackageInfo.ThreadId (PackageInfo.Start ? "&start=" PackageInfo.Start : "") (PackageInfo.Post ? "&p=" PackageInfo.Post : "") "&codebox=" PackageInfo.CodeBox "@" PackageInfo.Version

    PackageInfo.DependencyEntry := "github:" PackageInfo.Repository "@" (IsSemVer(Version) && !(Version ~= "^[~^><=]") ? "^" Version : Version)

    PackageInfo.DependencyEntry := "github:" PackageInfo.Repository "@" PackageInfo.Version ; MinimalInstall
    */
}

ReplaceInstallCommandVersion(InstallCommand, NewVersion) {
    if !InStr(InstallCommand, "@")
        return NewVersion
    else {
        return RegExReplace(InstallCommand, "@.*?(?= --main| --files| -m|$)", "@" NewVersion)
    }
}

DownloadPackageWithDependencies(PackageInfo, TempDir, Includes, CanUpdate:=false, MarkedForRemove:=[]) {
    if PackageInfo.HasProp("Preinstall") {
        Exec := ExecScript(PackageInfo.Preinstall, '"' TempDir '"')
        if Exec.ExitCode {
            WriteStdOut "Package preinstall script failed with ExitCode " Exec.ExitCode ", install aborted"
            return 0
        }
    }

    IsVersioned := PackageInfo.Version || (PackageInfo.RepositoryType = "archive")

    if CanUpdate && !PackageInfo.Version && PackageInfo.PackageName != "" && g_PackageJson["dependencies"].Has(PackageInfo.PackageName) {
        PackageInfo.Version := StrSplit(g_PackageJson["dependencies"][PackageInfo.PackageName], "@")[-1]
    }

    if PackageInfo.IsMain {
        PrevWorkingDir := A_WorkingDir
        A_WorkingDir := TempDir
        goto DownloadPackage
    }

    ; First download dependencies listed in index.json, except if we are updating our package
    if !CanUpdate && PackageInfo.Dependencies.Count {
        for DependencyName, DependencyVersion in PackageInfo.Dependencies {
            WriteStdOut "Starting install of dependency " DependencyName "@" DependencyVersion
            if !DownloadPackageWithDependencies(DependencyEntryToPackageInfo(DependencyName, DependencyVersion), TempDir, Includes)
                throw Error("Failed to install dependency", -1, DependencyName "@" DependencyVersion)
        }
    }

    if (!IsVersioned || PackageInfo.Global) && !CanUpdate && (PackageInfo.Version || PackageInfo.DependencyVersion) {
        if !g_Switches["local_install"] && g_GlobalInstalledPackages.Has(PackageInfo.PackageName) {
            for InstallDir, Projects in g_GlobalInstalledPackages[PackageInfo.PackageName] {
                Split := StrSplit(InstallDir, "@",, 2)
                if IsVersionCompatible(Split[2], PackageInfo.Version || PackageInfo.DependencyVersion) {
                    WriteStdOut("Found matching globally installed package " InstallDir ", skipping install`n")
                    PackageInfo.InstallName := InstallDir, PackageInfo.InstallVersion := Split[2]
                    if !Includes.Has(PackageInfo.PackageName)
                        Includes[PackageInfo.PackageName] := PackageInfo
                    return PackageInfo
                }
            }
        }
        if Includes.Has(PackageInfo.PackageName) && (Include := Includes[PackageInfo.PackageName]) && (DirExist(TempDir "\" Include.InstallName) || (!Include.Global && DirExist(g_LocalLibDir "\" Include.InstallName)) || (!g_Switches["local_install"] && DirExist(g_GlobalLibDir "\" Include.InstallName))) {
            WriteStdOut 'Package "' Include.InstallName '" already installed, skipping...`n'
            PackageInfo.InstallName := StrReplace(Include.InstallName, "\", "/")
            return Include
        }
    }

    DownloadPackage:

    VerifyPackageIsDownloadable(PackageInfo)
    if !IsVersioned && IsPackageInstalled(PackageInfo, Includes, [TempDir, g_LocalLibDir, g_GlobalLibDir]) && IsVersionCompatible(PackageInfo.Version, "=" PackageInfo.InstallVersion) {
        if CanUpdate
            WriteStdOut 'Package "' PackageInfo.PackageName "@" PackageInfo.Version '" has no matching updates available'
        else
            WriteStdOut 'Package "' PackageInfo.PackageName "@" PackageInfo.Version '" is already installed'
        return 0
    }

    FinalDirName := DownloadSinglePackage(PackageInfo, TempDir, g_LocalLibDir)

    if FinalDirName is Integer
        return FinalDirName

    if PackageInfo.HasProp("Postdownload") {
        A_Clipboard := PackageInfo.Postdownload
        Exec := ExecScript(PackageInfo.Postdownload, '"' TempDir "\" FinalDirName '"')
        if Exec.ExitCode {
            WriteStdOut "Package postdownload script failed with ExitCode " Exec.ExitCode ", install aborted"
            DirDelete('"' TempDir "\" FinalDirName '"')
            return 0
        }
    }

    if PackageInfo.Files.Length {
        DirCreateEx(TempDir "\" FinalDirName "~")
        NoMainName := PackageInfo.Main = "", WildcardFilesSet := false
        if PackageInfo.Files.Length = 1 && PackageInfo.Files[1] == PackageInfo.Main
            PackageInfo.Files[1] := "*.*", WildcardFilesSet := true
        if NoMainName {
            if PackageInfo.Files.Length = 1
                PackageInfo.Main := PackageInfo.Files[1]
            else
                SetPackageInfoMainFile(PackageInfo, TempDir, FinalDirName)
        } 
        MainFile := StrReplace(PackageInfo.Main, "/", "\")
        if !FileExist(TempDir "\" FinalDirName "\" MainFile) {
            Loop files TempDir "\" FinalDirName "\*.ah*", "R" {
                if A_LoopFileName = MainFile {
                    PackageInfo.Main := MainFile := StrSplit(A_LoopFileFullPath, TempDir "\" FinalDirName "\",, 2)[-1]
                    break
                }
            }
        }
        if NoMainName && PackageInfo.Files.Length = 1 && PackageInfo.Files[1] ~= "i)(?<!\*)\.ahk?\d?$" {
            PackageInfo.Main := StrSplit(MainFile, "\")[-1]
            FileMove(TempDir "\" FinalDirName "\" MainFile, TempDir "\" FinalDirName "~\" PackageInfo.Main)
        } else {
            Loop Files TempDir, "D" {
                TempDirFullPath := A_LoopFileFullPath
                break
            }
            for Pattern in PackageInfo.Files {
                Pattern := Trim(StrReplace(Pattern, "/", "\"), "\/")
                Loop files TempDirFullPath "\" FinalDirName "\" Pattern, "DF" (InStr(Pattern, "*.*") ? "R" : "") {
                    FileName := StrReplace(A_LoopFileFullPath, TempDirFullPath "\" FinalDirName,,,,1)
                    FileName := Trim(StrReplace(FileName, "/", "\"), "\/")

                    DirName := "", SplitName := StrSplit(FileName, "\")
                    if FileExist(TempDirFullPath "\" FinalDirName "\" FileName)
                        SplitName.Pop()
                    for SubDir in SplitName {
                        DirName .= SubDir "\"
                        if !DirExist(TempDirFullPath "\" FinalDirName "~\" DirName)
                            DirCreateEx(TempDirFullPath "\" FinalDirName "~\" DirName)
                    }

                    if DirExist(A_LoopFileFullPath)
                        DirMove(A_LoopFileFullPath, TempDir "\" FinalDirName "~\" FileName, 1)
                    else
                        FileMove(A_LoopFileFullPath, TempDir "\" FinalDirName "~\" FileName)
                }
            }
        }

        if WildcardFilesSet
            PackageInfo.Files[1] := PackageInfo.Main
        
        if !FileExist(TempDir "\" FinalDirName "~\" MainFile) {
            PackageInfo.Main := StrSplit(MainFile, "\")[-1]
            if DirExist(TempDir "\" FinalDirName "\" PackageInfo.Main)
                DirMove(TempDir "\" FinalDirName "\" PackageInfo.Main, TempDir "\" FinalDirName "~", 2)
            else if FileExist(TempDir "\" FinalDirName "\" PackageInfo.Main)
                FileMove(TempDir "\" FinalDirName "\" PackageInfo.Main, TempDir "\" FinalDirName "~\" PackageInfo.Main)
        }
        if FileExist(TempDir "\" FinalDirName "\LICENSE")
            FileMove(TempDir "\" FinalDirName "\LICENSE", TempDir "\" FinalDirName "~\LICENSE")
        DirDelete(TempDir "\" FinalDirName, 1)
        DirMove(TempDir "\" FinalDirName "~", TempDir "\" FinalDirName, 1)
    }

    if IsVersioned { ; A specific version was requested, in which case force the install
        if Includes.Has(PackageInfo.PackageName) && (Include := Includes[PackageInfo.PackageName]) && (DirExist(g_LocalLibDir "\" Include.InstallName) || DirExist(g_GlobalLibDir "\" Include.InstallName)) {
            InstalledPackages := QueryInstalledPackages()
            ForceRemovePackageWithDependencies(Include, InstalledPackages, Include.Global ? g_GlobalLibDir : g_LocalLibDir)
            Includes.Delete(PackageInfo.PackageName)
        }
    } else if CanUpdate {
        if Includes.Has(PackageInfo.PackageName) && (Include := Includes[PackageInfo.PackageName]) && (DirExist(g_LocalLibDir "\" Include.InstallName) || DirExist(g_GlobalLibDir "\" Include.InstallName)) && IsVersionCompatible(PackageInfo.Version, "^" Include.DependencyVersion) {
            ForceRemovePackage(Include, Include.Global ? g_GlobalLibDir : g_LocalLibDir, false)
            Includes.Delete(PackageInfo.PackageName)
        }
    }

    AddMainInclude:

    SetPackageInfoMainFile(PackageInfo, TempDir, FinalDirName)

    PackageInfo.InstallName := StrReplace(FinalDirName, "\", "/")
    PackageInfo.InstallVersion := PackageInfo.Version
    PackageInfo.InstallBuildMetadata := PackageInfo.BuildMetadata

    if !PackageInfo.IsMain {
        PackageInfo.Main := Trim(StrReplace(PackageInfo.Main, "/", "\"), "\/")
        Includes[PackageInfo.PackageName] := PackageInfo
    } 

    if DirExist(TempDir "\" FinalDirName) && FileExist(TempDir "\" FinalDirName "\package.json") {
        if PackageInfo.IsMain {
            TempDir .= "\" FinalDirName "\Lib"
        }

        PackageJson := LoadJson(TempDir "\" FinalDirName "\package.json")
        if PackageJson.Has("dependencies") {
            WriteStdOut "Found dependencies in extracted package manifest"
            for DependencyName, DependencyVersion in PackageJson["dependencies"] {
                WriteStdOut "Starting install of dependency " DependencyName "@" DependencyVersion
                DownloadPackageWithDependencies(DependencyName "@" DependencyVersion, TempDir, Includes)
            }
        }
    }

    if PackageInfo.HasProp("Postinstall") {
        Exec := ExecScript(PackageInfo.Postinstall, '"' TempDir '"')
        if Exec.ExitCode {
            WriteStdOut "Package postinstall script failed with ExitCode " Exec.ExitCode ", install aborted"
            return 0
        }
    }

    return PackageInfo
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
                PackageInfo.Main := (Name := RemoveAhkSuffix(Info["filename"])) ".ahk"
                if !PackageInfo.Name
                    PackageInfo.Name := Name
                break
            }
        }
        PackageInfo.PackageName := PackageInfo.Author "/" RemoveAhkSuffix(PackageInfo.Name)
        PackageInfo.SourceAddress := "https://gist.github.com/raw/" PackageInfo.Repository "/" PackageInfo.FullVersion "/" PackageInfo.Main

        WriteStdOut('Downloading gist as package "' PackageInfo.PackageName '@' PackageInfo.Version '"')
        Download PackageInfo.SourceAddress, TempDir "\" TempDownloadDir "\" PackageInfo.Main
        goto AfterDownload
    } else if PackageInfo.RepositoryType = "forums" {
        if PackageInfo.Version = "latest" || PackageInfo.BuildMetadata {
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
            PackageInfo.Name := RemoveAhkSuffix(PackageInfo.Name)
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

        if !PackageInfo.Version || PackageInfo.Version = "latest" || PackageInfo.BuildMetadata {
            Hash := SubStr(MD5(Code), 1, 10)
            if IsVersionMD5(PackageInfo.Version) && Hash != PackageInfo.Version
                throw Error("Download from forums succeeded, but there was a package hash mismatch", -1, "Found " Hash " but expected " PackageInfo.BuildMetadata)
            PackageInfo.BuildMetadata := (PackageInfo.InstallVersion || PackageInfo.DependencyVersion || A_NowUTC)
            PackageInfo.Version := Hash
        }

        FileAppend(Code, TempDir "\" TempDownloadDir "\" PackageInfo.Name ".ahk")

        PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name
        ;FileAppend(JSON.Dump(Map("repository", Map("type", "forums", "url", "https://www.autohotkey.com/boards/viewtopic.php?t=" PackageInfo.ThreadId "&codebox=" PackageInfo.CodeBox), "author", PackageInfo.Author, "name", PackageInfo.PackageName, "version", PackageInfo.Version), true), TempDir "\" TempDownloadDir "\package.json")
        goto AfterDownload
    } else if PackageInfo.RepositoryType = "github" {
        if !PackageInfo.DependencyEntry && !g_Index.Has(PackageInfo.PackageName) {
            Version := PackageInfo.DependencyVersion || PackageInfo.Version || PackageInfo.InstallVersion
        }
    } else if PackageInfo.RepositoryType = "ahk" {
        PackageInfo.Main := StrSplit(StrReplace(PackageInfo.Main, "\", "/"), "/")[-1]
        Download PackageInfo.SourceAddress, TempDir "\" TempDownloadDir "\" (PackageInfo.Main || StrSplit(PackageInfo.SourceAddress, "/")[-1])
        goto AfterDownload
    }

    ZipName := PackageInfo.ZipName
    if !FileExist(g_CacheDir "\" ZipName) {
        WriteStdOut('Downloading package "' PackageInfo.PackageName '"')
        Download PackageInfo.SourceAddress, g_CacheDir "\" ZipName
    }

    if PackageInfo.RepositoryType = "archive"
        PackageInfo.Version := SubStr(HashFile(g_CacheDir "\" ZipName, 3), 1, 7)

    WriteStdOut('Extracting package from "' ZipName '"')
    DirCopy g_CacheDir "\" ZipName, TempDir "\" TempDownloadDir, true

    DirCount := 0, LastDir := ""
    Loop Files TempDir "\" TempDownloadDir "\*.*", "DF"
        DirCount++, LastDir := A_LoopFileFullPath, LastDirName := A_LoopFileName

    if (DirCount = 1) && DirExist(LastDir) {
        if PackageInfo.RepositoryType = "archive" {
            PackageInfo.Name := PackageInfo.Name || RemoveAhkSuffix(LastDirName), PackageInfo.Author := PackageInfo.Author || "Unknown", PackageInfo.PackageName := PackageInfo.PackageName || PackageInfo.Author "/" PackageInfo.Name
        }
        DirMove(LastDir, TempDir "\" TempDownloadDir, 2)
    }

    if !PackageInfo.IsMain && FileExist(TempDir "\" TempDownloadDir "\package.json") && !g_Index.Has(PackageInfo.PackageName) {
        PackageJson := LoadPackageJson(TempDir "\" TempDownloadDir)
        if PackageJson.Has("name") {
            if InStr(PackageJson["name"], "/") {
                PackageInfo.PackageName := PackageJson["name"]
                Split := ParsePackageName(PackageJson["name"])
                PackageInfo.Name := RemoveAhkSuffix(Split.Name), PackageInfo.Author := Split.Author
            } else {
                PackageInfo.Name := RemoveAhkSuffix(PackageJson["name"]), PackageInfo.PackageName := PackageInfo.PackageName || PackageInfo.Author "/" PackageInfo.Name
            }
        }
        ;if PackageJson.Has("version")
        ;    PackageInfo.Version := PackageJson["version"]
    }

    AfterDownload:

    FinalDirName := PackageInfo.Author "\" PackageInfo.Name "@" PackageInfo.Version

    if PackageInfo.RepositoryType = "forums" && PackageInfo.BuildMetadata != "" {
        Loop files LibDir "\" PackageInfo.Author "\*.*", "D" {
            if RegExMatch(A_LoopFileName, "i)^\Q" PackageInfo.Name "@\E.*\+\Q" PackageInfo.BuildMetadata "\E$") {
                FinalDirName := PackageInfo.Author "\" A_LoopFileName
                break
            }
        }
    }

    if DirExist(TempDir "\" FinalDirName) || DirExist(LibDir "\" FinalDirName) {
        WriteStdOut 'Package "' StrReplace(FinalDirName, "\", "/") '" already installed or up-to-date, skipping...`n'
        DirDelete(TempDir "\" TempDownloadDir, true)
        return 1
    }

    DirCreate(TempDir "\" StrSplit(FinalDirName, "\")[1])
    DirMove(TempDir "\" TempDownloadDir, TempDir "\" FinalDirName)
    return FinalDirName
}

IsGithubMinimalInstallPossible(PackageInfo, IgnoreVersion := false) {
    if !IgnoreVersion && !IsVersionSha(PackageInfo.Version)
        return false
    if !PackageInfo.Files.Length ; In this case never allow minimal install
        return false
    if PackageInfo.Files.Length = 1 {
        if PackageInfo.Main != "" ; Files started out empty and Main was pushed into Files, so also ignore this one
            return false
        if PackageInfo.Main = "" && PackageInfo.Files[1] ~= "i)(?<!\*)\.ahk?\d?$"
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

GithubDownloadMinimalInstall(PackageInfo, Path) {
    WriteStdOut('Downloading minimal install for package "' PackageInfo.PackageName '"')

    Path := Trim(Path, "\/")
    Repo := StrSplit(PackageInfo.Repository, "/")

    try Download("https://github.com/" Repo[1] "/" Repo[2] "/raw/" PackageInfo.Version "/LICENSE", Path "\LICENSE")
    if InStr(FileRead(Path "\LICENSE"), "<!DOCTYPE html>")
        FileDelete(Path "\LICENSE")

    if PackageInfo.Files.Length = 1 {
        PackageInfo.MainPath := PackageInfo.Files[1], PackageInfo.Main := StrSplit(PackageInfo.Main || PackageInfo.MainPath, "/")[-1]
        try Download("https://github.com/" Repo[1] "/" Repo[2] "/raw/" PackageInfo.Version "/"  PackageInfo.MainPath, Path "\" PackageInfo.Main)
        catch
            throw Error("Download failed", -1, '"' Path "\" PackageInfo.Main '@' PackageInfo.Version '" from GitHub repo "' Repo[1] "/" Repo[2] '"')
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
    }
    return 1
}

SetPackageInfoMainFile(PackageInfo, TempDir, FinalDirName) {
    if !PackageInfo.Main {
        Loop Files TempDir "\" FinalDirName "\*.ah*" {
            if (A_LoopFileName = (PackageInfo.Name "." A_LoopFileExt)) || (A_LoopFileName ~= "i)^(main|export)\.ahk?\d?") || (PackageInfo.Name ~= "\.ahk?\d?$" && StrSplitLast(A_LoopFileName, ".")[1] = StrSplitLast(PackageInfo.Name, ".")[1]) {
                PackageInfo.Main := A_LoopFileName
                break
            }
        }
        if !PackageInfo.Main && DirExist(TempDir "\" FinalDirName "\Lib") {
            Loop Files TempDir "\" FinalDirName "\Lib\*.ah*" {
                if (A_LoopFileName = (PackageInfo.Name "." A_LoopFileExt)) || (A_LoopFileName ~= "i)^(main|export)\.ahk?\d?") || (PackageInfo.Name ~= "\.ahk?\d?$" && StrSplitLast(A_LoopFileName, ".")[1] = StrSplitLast(PackageInfo.Name, ".")[1]) {
                    PackageInfo.Main := "Lib\" A_LoopFileName
                    break
                }
            }
        }
        if !PackageInfo.Main {
            Loop Files TempDir "\" FinalDirName "\*.ah*", "R" {
                if PackageInfo.Main
                    throw Error("Unable to lock onto a specific main file", -1)
                PackageInfo.Main := StrSplit(A_LoopFileFullPath, "\" FinalDirName "\")[-1]
                if PackageInfo.RepositoryType = "archive"
                    break
            }
        }
        PackageInfo.Main := Trim(PackageInfo.Main, "\/")
    }
}

VerifyPackageIsDownloadable(PackageInfo) {
    if PackageInfo.RepositoryType = "github" && IsVersionSha(PackageInfo.Version) {
        if PackageInfo.Files.Length > 1 {
            Repo := StrSplit(PackageInfo.Repository, "/")
            ZipName := (repo.Length = 3 ? Repo[3] : QueryGitHubRepo(PackageInfo.Repository)["default_branch"]) ".zip"
            PackageInfo.SourceAddress := "https://github.com/" Repo[1] "/" Repo[2] "/archive/refs/heads/" ZipName
            PackageInfo.ZipName := Repo[1] "_" Repo[2] "_" PackageInfo.Version "-" ZipName
        } else if !PackageInfo.Files.Length {
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
            if !((commits := (IsGithubMinimalInstallPossible(PackageInfo, true) ? QueryGitHubRepo(PackageInfo.Repository, "commits?path=" (PackageInfo.Files.Length ? PackageInfo.Files[1] : PackageInfo.Main)) : QueryGitHubCommits(PackageInfo.Repository))) && commits is Array && commits.Length)
                throw Error("Unable to find releases or commits for the specified GitHub repository", -1, PackageInfo.PackageName)
            
            PackageInfo.Version := PackageInfo.Version || PackageInfo.InstallVersion || PackageInfo.DependencyVersion
            if RegExMatch(PackageInfo.Version, "\d+", &NumMatch) && (StrLen(NumMatch[0]) = 14) {
                if !(commit := FindMatchingGithubCommitDate(commits, PackageInfo.Version))
                    throw Error("No matching commit date found among GitHub commits")
                PackageInfo.Version := SubStr(commit["sha"], 1, 7)
            } else
                PackageInfo.Version := SubStr(commits[1]["sha"], 1, 7)

            WriteStdOut("No GitHub releases found, falling back to the default branch.")
            if IsGithubMinimalInstallPossible(PackageInfo)
                return

            ZipName := (repo.Length = 3 ? repo[3] : QueryGitHubRepo(PackageInfo.Repository)["default_branch"]) ".zip"
            PackageInfo.SourceAddress := "https://github.com/" Repo[1] "/" Repo[2] "/archive/refs/heads/" ZipName
            PackageInfo.ZipName := Repo[1] "_" Repo[2] "_" PackageInfo.Version "-" ZipName
        } else {
            if !(release := FindMatchingGithubReleaseVersion(releases, PackageInfo.Version || PackageInfo.InstallVersion || PackageInfo.DependencyVersion))
                throw Error("No matching version found among GitHub releases")

            PackageInfo.Version := release["tag_name"]
            if release.Has("assets") && release["assets"].Length {
                asset := release["assets"][1]
                if asset["name"] ~= "i)\.ahk?\d?$" {
                    PackageInfo.Main := PackageInfo.Main || asset["name"]
                    PackageInfo.Files := [PackageInfo.Main]
                    PackageInfo.RepositoryType := "ahk"
                    PackageInfo.ZipName := Repo[1] "_" Repo[2] "_" PackageInfo.Version "-" PackageInfo.Main
                    PackageInfo.SourceAddress := asset["browser_download_url"]
                } else {
                    PackageInfo.ZipName := Repo[1] "_" Repo[2] "_" PackageInfo.Version "-" asset["name"]
                    PackageInfo.SourceAddress := asset["browser_download_url"]
                }
            } else {
                PackageInfo.ZipName := Repo[1] "_" Repo[2] "_" PackageInfo.Version ".zip"
                PackageInfo.SourceAddress := release["zipball_url"]
            }
        }
    } else if PackageInfo.RepositoryType = "archive" {
        PackageInfo.Version := A_YYYY A_MM A_DD "+" SubStr(MD5(PackageInfo.Repository), 1, 10)
        PackageInfo.ZipName := "archive_" PackageInfo.Version (RegExMatch(PackageInfo.Repository, "i)\.tar\.gz$") ? ".tar.gz" : "." StrSplit(PackageInfo.Repository, ".")[-1])
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
        PackageInfo.Version := PackageInfo.Version || PackageInfo.InstallVersion || PackageInfo.DependencyVersion
        if PackageInfo.Version != "latest" && !PackageInfo.BuildMetadata {
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
        PackageDir := LibDir "\" InstalledPackage.InstallName
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
        if !IsObject(Info) {
            g_Index.%PackageName% := Info
            continue
        }
        if !Info.Has("author")
            Info["author"] := StrSplit(PackageName, "/")[1]
        if !Info.Has("repository")
            Info["repository"] := Map("type", "github", "url", PackageName)
        else
            StandardizeRepositoryInfo(Info)
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
    g_Config.Default := ""
    if g_Config["global_install"]
        g_Switches["global_install"] := true
}

DownloadPackageIndex() {
    WriteStdOut "Checking for index updates..."
    try {
        Download(g_GitHubRawBase "assets/index.json", A_ScriptDir "\assets\~index.json")
        if (DownloadedIndexContent := FileRead(A_ScriptDir "\assets\~index.json")) != FileRead(A_ScriptDir "\assets\index.json") {
            DownloadedIndex := JSON.Load(DownloadedIndexContent)
            if Integer(StrSplit(DownloadedIndex['version'], ".")[1]) = Integer(StrSplit(g_Index.Version, ".")[1]) {
                FileMove(A_ScriptDir "\assets\~index.json", A_ScriptDir "\assets\index.json", 1)
                if !g_Config.Has("auto_update_index_daily") || g_Config["auto_update_index_daily"] {
                    g_Config["auto_update_index_daily"] := A_NowUTC
                    SaveSettings()
                }
                SaveSettings()
                WriteStdOut "Index successfully updated to latest version"
            } else {
                WriteStdOut "Incompatible index.json version, ARIS update is recommended"
            }
        } else
            WriteStdOut "Index is already up-to-date"
    } catch {
        WriteStdOut "Failed to download index.json"
    }
    try FileDelete(A_ScriptDir "\assets\~index.json")
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
    LibDir := path "Lib\Aris"
    Packages := Mapi()
    if !FileExist(LibDir "\packages.ahk")
        return Packages

    Loop parse FileRead(LibDir "\packages.ahk"), "`n", "`r" {
        if !(A_LoopField ~= "i)^\s*#include")
            continue

        if !RegExMatch(A_LoopField, "i)^#include (?:<Aris|\.|%A_MyDocuments%)(?:\\|\/)([^>]+?)(?:>|\.ahk)(?: `; )?(.*)?", &IncludeInfo := "")
            continue
        Path := StrReplace(IncludeInfo[1], "/", "\")

        if !FileExist(LibDir "\" Path ".ahk")
            continue

        ExtraInfo := RegExReplace(FileRead(LibDir "\" Path ".ahk"), "i)^#include (\.|%A_MyDocuments%)\\(([^@]+\\))*")
        ExtraInfoSplit := StrSplit(ExtraInfo, "\")

        PackageInfo := InstallInfoToPackageInfo(Path, StrSplit(ExtraInfoSplit[1], "@",, 2)[2], ExtraInfoSplit[-1], IncludeInfo.Count = 2 ? IncludeInfo[2] : "")
        if !PackageJson["dependencies"].Has(PackageInfo.PackageName)
            continue
        PackageInfo.Global := !DirExist(LibDir "\" Path "@" PackageInfo.InstallVersion)
        Packages[PackageInfo.PackageName] := PackageInfo
    }

    return Packages
}

QueryPackageDependencies(path := ".\", From := "") {
    path := Trim(path, "\/") "\"
    LibDir := path "\Lib\Aris"
    Packages := Mapi()
    if !From || From = "package.json" {
        PackageJson := path = ".\" ? g_PackageJson : LoadPackageJson(path)
        for PackageName, VersionRange in PackageJson["dependencies"] {
            Packages[PackageName] := DependencyEntryToPackageInfo(PackageName, VersionRange)
        }
    }
    if (!From || From = "packages.ahk") && FileExist(LibDir "\packages.ahk") {
        for Include in ReadIncludesFromFile(LibDir "\packages.ahk") {
            if Packages.Has(Include.PackageName) {
                Packages[Include.PackageName].InstallVersion := Include.InstallVersion
                Packages[Include.PackageName].Main := Include.Main
            } else
                Packages[Include.PackageName] := Include
        }
        return Packages
    } 
    if !From || (From && From != "packages.ahk") {
        Loop files (From ? From : path "*.ah*") {
            for Include in ReadIncludesFromFile(A_LoopFileFullPath)
                Packages[Include.PackageName] := Include
        }
    }
    return Packages
}

ReadIncludesFromFile(path) {
    Packages := []
    if !FileExist(path)
        return Packages
    Loop parse FileRead(path), "`n", "`r" {
        if !(A_LoopField ~= "i)^\s*#include")
            continue
        if !RegExMatch(A_LoopField, "i)^#include (?:<Aris|\.)(?:\\|\/)([^>]+?)(?:>|\.ahk)(?: `; )?(.*)?", &IncludeInfo := "")
            continue

        try Packages.Push(InstallInfoToPackageInfo(IncludeInfo[1],,, IncludeInfo.Count = 2 ? IncludeInfo[2] : ""))
        catch as err {
            WriteStdOut err.Message (err.Extra ? ": " err.Extra : "") 
        }
    }
    return Packages
}

CleanPackages() {
    InstalledMap := Map(), Dependencies := Map()
    for PackageName, PackageInfo in g_InstalledPackages {
        InstalledMap[PackageInfo.InstallName] := PackageInfo
        InstalledMap[PackageInfo.PackageName] := PackageInfo
    }

    WriteStdOut "Removing unused entries from package.json"
    if FileExist("package.json") {
        for Dependency, Version in g_PackageJson["dependencies"] {
            if InstalledMap.Has(Dependency)
                Dependencies[Dependency] := Version
            else
                WriteStdOut "Removing unused dependency " Dependency ": " Version
        }
        g_PackageJson["dependencies"] := Dependencies
        if (NewContent := JSON.Dump(g_PackageJson, true)) && (NewContent != FileRead("package.json"))
            FileOpen("package.json", "w").Write(NewContent)
    }

    WriteStdOut "Removing unused global package entries"
    for PackageName, InstallInfo in g_GlobalInstalledPackages.Clone() {
        for InstallName, ProjectArray in InstallInfo.Clone() {
            Loop ArrLen := ProjectArray.Length {
                if !DirExist(ProjectArray[ArrLen-A_Index+1]) {
                    WriteStdOut "Project folder `"" ProjectArray[ArrLen-A_Index+1] "`" not found, deleting entry for " PackageName
                    ProjectArray.RemoveAt(ArrLen-A_Index+1)
                }
            }
            if !ProjectArray.Length
                InstallInfo.Delete(InstallName)
        }
        if !InstallInfo.Count
            g_GlobalInstalledPackages.Delete(PackageName)
    }

    for LibDir in [g_LocalLibDir, g_GlobalLibDir] {
        WriteStdOut "Cleaning " (LibDir = g_LocalLibDir ? "local" : "global") " library directory"
        InstalledPackageMap := LibDir = g_LocalLibDir ? InstalledMap : g_GlobalInstalledPackages
        Loop files LibDir "\*.*", "D" {
            Author := A_LoopFileName
            Loop files A_LoopFileFullPath "\*.*", "DF" {
                if DirExist(A_LoopFileFullPath)
                    Name := A_LoopFileName, DeleteFunc := DirDelete.Bind(,true)
                else
                    Name := StrSplitLast(A_LoopFileName, ".")[1], DeleteFunc := FileDelete
                if !InstalledPackageMap.Has(Author "/" Name) {
                    WriteStdOut "Deleting unused " (DeleteFunc = FileDelete ? "file" : "directory") " Author\" A_LoopFileName
                    DeleteFunc(A_LoopFileFullPath)
                }
            }
            try DirDelete(A_LoopFileFullPath)
        }
    }

    if !FileExist(g_LocalLibDir "\packages.ahk")
        return

    WriteStdOut "Removing unused entries from packages.ahk"
    OldContent := NewContent := FileRead(g_LocalLibDir "\packages.ahk")
    Loop parse NewContent, "`n", "`r" {
        if !(A_LoopField ~= "i)^\s*#include")
            continue

        if !RegExMatch(A_LoopField, "i)^#include (?:<Aris|\.|%A_MyDocuments%)(?:\\|\/)([^>]+?)(?:>|\.ahk)(?: `; )?(.*)?", &IncludeInfo := "")
            continue

        if InstalledMap.Has(IncludeInfo[1])
            continue

        WriteStdOut "Removing unused include: " A_LoopField
        NewContent := StrReplace(NewContent, A_LoopField "`n")
    }
    if OldContent != NewContent
        FileOpen(g_LocalLibDir "\packages.ahk", "w").Write(NewContent)

    WriteStdOut "Cleaning packages complete"
}

RemovePackageFromGlobalInstallEntries(PackageInfo) {
    global g_GlobalInstalledPackages
    ChangesMade := false, NoOtherDependencies := true
    if g_GlobalInstalledPackages.Has(PackageInfo.PackageName) && g_GlobalInstalledPackages[PackageInfo.PackageName].Has(PackageInfo.InstallName) {
        for j, Project in g_GlobalInstalledPackages[PackageInfo.PackageName][PackageInfo.InstallName] {
            if Project = A_WorkingDir {
                g_GlobalInstalledPackages[PackageInfo.PackageName][PackageInfo.InstallName].RemoveAt(j), ChangesMade := true
                break
            }
        }
        if !g_GlobalInstalledPackages[PackageInfo.PackageName][PackageInfo.InstallName].Length
            g_GlobalInstalledPackages[PackageInfo.PackageName].Delete(PackageInfo.InstallName), ChangesMade := true
        else
            NoOtherDependencies := false
    }
    if g_GlobalInstalledPackages.Has(PackageInfo.PackageName) && !g_GlobalInstalledPackages[PackageInfo.PackageName].Count
        g_GlobalInstalledPackages.Delete(PackageInfo.PackageName), ChangesMade := true
    if ChangesMade
        SaveGlobalInstalledPackages()
    return NoOtherDependencies
}

FindMatchingGithubReleaseVersion(releases, target) {
    CompareFunc := GetVersionRangeCompareFunc(target)

    for release in releases {
        if CompareFunc(release["tag_name"])
            return release
    }
    return ""
}

FindMatchingGithubCommitDate(commits, target) {
    CompareFunc := GetVersionRangeCompareFunc(target)

    for commit in commits {
        if CompareFunc(commit["date"] := RegExReplace(commit["commit"]["committer"]["date"], "[^\d]"))
            return commit
    }
    return ""
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
    if !token && g_Config.Has("github_token")
        token := g_Config["github_token"]
    if token
        whr.SetRequestHeader("Authorization", "Bearer " token)
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
            if !(RegExMatch(Entry[3], "i)start=(\d+)", &match:="") && match[1] = PackageInfo.Start)
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
        Matches.Push({Repository:Entry[3], Version:Entry[2], Digest:Entry[6]})
    }
    return Matches
}

MergeJsonInfoToPackageInfo(JsonInfo, PackageInfo) {
    if !PackageInfo.Dependencies.Count && JsonInfo.Has("dependencies")
        PackageInfo.Dependencies := JsonInfo["dependencies"]
    if !PackageInfo.Repository {
        PackageInfo.Repository := JsonInfo["repository"]["url"], PackageInfo.RepositoryType := JsonInfo["repository"]["type"]
        ParseRepositoryData(PackageInfo)
    }
    if !PackageInfo.Files.Length {
        if JsonInfo.Has("files")
            PackageInfo.Files := JsonInfo["files"] is String ? [JsonInfo["files"]] : JsonInfo["files"]
    }
    if !PackageInfo.Main && JsonInfo.Has("main")
        PackageInfo.Main := JsonInfo["main"]
    if JsonInfo.Has("scripts") {
        if !PackageInfo.HasProp("Preinstall") && JsonInfo["scripts"].Has("preinstall")
            PackageInfo.Preinstall := JsonInfo["scripts"]["preinstall"]
        if !PackageInfo.HasProp("Postinstall") && JsonInfo["scripts"].Has("postinstall")
            PackageInfo.Postinstall := JsonInfo["scripts"]["postinstall"]
        if !PackageInfo.HasProp("Postdownload") && JsonInfo["scripts"].Has("postdownload")
            PackageInfo.PostDownload := JsonInfo["scripts"]["postdownload"]
    }
    return PackageInfo
}

MergeMainFileToFiles(PackageInfo, MainFile) {
    if MainFile = ""
        return
    MainFileName := StrSplitLast(MainFile, "/")[-1]
    if PackageInfo.Files.Length = 1 && StrSplitLast(PackageInfo.Files[1], "/")[-1] = MainFileName
        PackageInfo.Main := ""
    for PackageFile in PackageInfo.Files {
        if InStr(PackageFile, "*") || StrSplitLast(PackageFile, "/")[-1] = MainFileName
            return
    }
    PackageInfo.Files.Push(MainFile)
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
            PackageInfo.Name := RemoveAhkSuffix(SplitId[1]), PackageInfo.Author := ""
        case 2: ; "Author/Package"
            PackageInfo.Author := SplitId[1], PackageInfo.Name := RemoveAhkSuffix(SplitId[2])
        default:
            throw ValueError("Invalid package name", -1, PackageName)
    }
    PackageInfo.PackageName := PackageInfo.Author "/" PackageInfo.Name
    return PackageInfo
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

WriteStdOut(msg) => FileAppend(msg "`n", "*")
WriteErrorStdOut(exception, mode) => (WriteStdOut("Uncaught error on line " exception.Line ": " exception.Message "`n" (exception.Extra ? "`tSpecifically: " exception.Extra "`n" : "")), 1)