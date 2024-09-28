LaunchGui() {
    WriteStdOut.DefineProp("call", {call:(this, msg) => g_MainGui.Tabs.Value = 1 ? g_MainGui.Tabs.Package.Metadata.Value .= msg "`n" : g_MainGui.Tabs.Index.Metadata.Value .= msg "`n"})

    g_MainGui.OnEvent("Size", GuiReSizer)
    g_MainGui.OnEvent("Close", (*) => ExitApp())

    g_MainGui.FolderTV := g_MainGui.Add("TreeView", "r25 w200", "Package files")
    g_MainGui.FolderTV.X := 10, g_MainGui.FolderTV.Height := -50, g_MainGui.FolderTV.WidthP := 0.3
    g_MainGui.FolderTV.OnEvent("ContextMenu", ShowFolderTVContextMenu)
    LoadPackageFolder(g_Config.Has("last_project_directory") && DirExist(g_Config["last_project_directory"]) ? g_Config["last_project_directory"] : A_WorkingDir)

    g_MainGui.PackageJson := LoadPackageJson()
    g_MainGui.AddStatusBar(, g_MainGui.PackageJson["name"] ? (g_MainGui.PackageJson["name"] "@" (g_MainGui.PackageJson["version"] || "undefined-version")) : "Undefined package: add package name and version in metadata.")
    g_MainGui.LoadPackageBtn := g_MainGui.AddButton(, "Load package")
    g_MainGui.LoadPackageBtn.Y := -45
    g_MainGui.ModifyMetadata := g_MainGui.AddButton("x+27", "Modify metadata")
    g_MainGui.ModifyMetadata.Anchor := g_MainGui.FolderTV, g_MainGui.ModifyMetadata.AnchorIn := false, g_MainGui.ModifyMetadata.YP := 1.0, g_MainGui.ModifyMetadata.Y := 5, g_MainGui.ModifyMetadata.XP := 1.0, g_MainGui.ModifyMetadata.X := -92
    g_MainGui.ModifyMetadata.OnEvent("Click", LaunchModifyMetadataGui)
    g_MainGui.LoadPackageBtn.OnEvent("Click", (*) => (dir := DirSelect("*" g_MainGui.CurrentFolder), dir ? (LoadPackageFolder(dir), PopulateTabs()) : ""))

    g_MainGui.Tabs := g_MainGui.AddTab3("w410 h395 x220 y6", ["Current package", "Index", "Settings"])
    g_MainGui.Tabs.UseTab(1)
    g_MainGui.Tabs.XP := 0.30, g_MainGui.Tabs.X := 15, g_MainGui.Tabs.W := -5, g_MainGui.Tabs.H := -25

    P := g_MainGui.Tabs.Package := {}
    P.LV := g_MainGui.Add("ListView", "r10 w390 Section -Multi", ["Package name", "Version", "Allowed versions", "Installed", "In index"])
    P.LV.W := -15
    P.LV.OnEvent("ItemSelect", PackageLVItemSelected)
    P.ReinstallBtn := g_MainGui.AddButton("w50", "Reinstall")
    P.ReinstallBtn.OnEvent("Click", PackageAction.Bind(P, "reinstall"))
    P.RemoveBtn := g_MainGui.AddButton("x+10 yp+0 w50", "Remove")
    P.RemoveBtn.OnEvent("Click", PackageAction.Bind(P, "remove"))
    P.UpdateBtn := g_MainGui.AddButton("x+10 yp+0 w50", "Update")
    P.UpdateBtn.OnEvent("Click", PackageAction.Bind(P, "update"))
    P.AddBtn := g_MainGui.AddButton("x+10 yp+0 w50", "Add")
    P.AddBtn.OnEvent("Click", PackageAction.Bind(P, "install-external"))
    P.UpdateLatestBtn := g_MainGui.AddButton("x+10 yp+0", "Force update to latest")
    P.UpdateLatestBtn.OnEvent("Click", PackageAction.Bind(P, "update-latest"))
    P.Metadata := g_MainGui.Add("Edit", "xs y+10 w390 h140 ReadOnly")
    P.Metadata.W := -15, P.Metadata.H := -35

    PopulatePackagesTab(P)

    g_MainGui.Tabs.UseTab(2)

    I := g_MainGui.Tabs.Index := {}
    I.LV := g_MainGui.Add("ListView", "r10 w390 Section -Multi", ["Package name", "Installed version", "Allowed versions", "Source"])
    I.LV.W := -15, I.LV.HP := 0.4
    I.LV.OnEvent("ItemSelect", IndexLVItemSelected)
    I.SearchText := g_MainGui.Add("Text",, "Search:")

    AnchorUnder := (o, to, X, Y) => (o.Anchor := to, o.AnchorIn := false, o.YP := 1.0, o.Y := Y, o.X := X)
    AnchorAfter := (o, to, X, Y) => (o.Anchor := to, o.AnchorIn := false, o.XP := 1.0, o.Y := Y, o.X := X)

    AnchorUnder(I.SearchText, I.LV, 5, 7)
    I.Search := g_MainGui.Add("Edit", "x+5 yp-2 -Multi")
    AnchorUnder(I.Search, I.LV, 45, 5)
    I.Search.OnEvent("Change", OnIndexSearch)
    I.SearchByStartCB := g_MainGui.Add("Checkbox", "x+10 yp+4", "Match start")
    AnchorAfter(I.SearchByStartCB, I.Search, 7, 3)
    I.SearchByStartCB.OnEvent("Click", (*) => OnIndexSearch(I.Search))
    I.SearchCaseSenseCB := g_MainGui.Add("Checkbox", "x+5 yp", "Match case")
    AnchorAfter(I.SearchCaseSenseCB, I.SearchByStartCB, 5, 0)
    I.SearchCaseSenseCB.OnEvent("Click", (*) => OnIndexSearch(I.Search))

    I.InstallBtn := g_MainGui.AddButton("xs y+8 w60", "Install")
    AnchorUnder(I.InstallBtn, I.LV, 5, 30)
    I.InstallBtn.OnEvent("Click", PackageAction.Bind(I, "install"))
    I.QueryVersionBtn := g_MainGui.AddButton("x+10 yp+0", "Query versions")
    AnchorAfter(I.QueryVersionBtn, I.InstallBtn, 5, 0)
    I.QueryVersionBtn.OnEvent("Click", LaunchVersionSelectionGui)
    I.UpdateIndexBtn := g_MainGui.AddButton("x+10 yp+0", "Update index")
    AnchorAfter(I.UpdateIndexBtn, I.QueryVersionBtn, 5, 0)
    I.UpdateIndexBtn.OnEvent("Click", (*) => (UpdatePackageIndex(), PopulateIndexTab(I)))
    I.Metadata := g_MainGui.Add("Edit", "xs y+10 w390 h120 ReadOnly")
    I.Metadata.YP := 0.4, I.Metadata.Y := 90, I.Metadata.H := -30, I.Metadata.W := -15

    PopulateIndexTab(I)

    g_MainGui.Tabs.UseTab(3)

    g_MainGui.AddText("Section", "Github private token:")
    S := g_MainGui.Tabs.Settings := {}
    S.GithubToken := g_MainGui.AddEdit("x+5 yp-3 w280 r1", g_Config.Has("github_token") ? g_Config["github_token"] : "")
    S.AddRemoveFromPATH := g_MainGui.AddButton("xs y+5 w150", (IsArisInPATH() ? "Remove Aris from PATH" : "Add Aris to PATH"))
    S.AddRemoveFromPATH.OnEvent("Click", (btnCtrl, *) => btnCtrl.Text = "Remove Aris from PATH" ? (RemoveArisFromPATH(), btnCtrl.Text := "Add Aris to PATH") : (AddArisToPATH(), btnCtrl.Text := "Remove Aris from PATH") )
    S.SaveSettings := g_MainGui.AddButton("xs y+5", "Save settings")
    S.SaveSettings.OnEvent("Click", (*) => (ApplyGuiConfigChanges(), SaveSettings(true)))

    g_MainGui.Tabs.UseTab(0)

    g_MainGui.Show("w640 h425")
    WinRedraw(g_MainGui) ; Prevents the edit box from sometimes being black
}

LVGetPackageInfo(LV) {
    Selected := LV.GetNext(0)
    if !Selected
        return 0
    return {PackageName: LV.GetText(Selected, 1), Version: LV.GetText(Selected, 2)}
}

PackageAction(Tab, Action, Btn, *) {
    if Action != "install-external" {
        PackageInfo := LVGetPackageInfo(Tab.LV)
        if !PackageInfo {
            ToolTip "Select a package first!"
            SetTimer ToolTip, -3000
            return
        }
    }
    Tab.Metadata.Value := ""
    switch Action, 0 {
        case "reinstall":
            RemovePackage(PackageInfo.PackageName "@" PackageInfo.Version, false)
            InstallPackage(PackageInfo.PackageName "@" PackageInfo.Version)
        case "remove":
            RemovePackage(PackageInfo.PackageName "@" PackageInfo.Version)
        case "update":
            InstallPackage(PackageInfo.PackageName "@" g_InstalledPackages[PackageInfo.PackageName].DependencyVersion, 1)
        case "update-latest":
            InstallPackage(PackageInfo.PackageName "@latest")
        case "install":
            Result := InstallPackage(PackageInfo.PackageName)
            if !Result && g_Index.Has(PN := PackageInfo.PackageName) && g_Index[PN].Has("repository") && (Repo := g_Index[PN]["repository"] is String ? g_Index[PN]["repository"] : g_Index[PN]["repository"]["url"]) && Repo ~= "forums:|autohotkey\.com" {
                WriteStdOut("`nRetrying to download latest version from AutoHotkey forums...")
                InstallPackage(PackageInfo.PackageName "@latest")
            }
        case "install-external":
            IB := InputBox('Install a package from a non-index source.`n`nInsert a source (GitHub repo, Gist, archive file URL) from where to install the package.`n`nIf installing from a GitHub repo, this can be "Username/Repo" or "Username/Repo@Version" (queries from releases) or "Username/Repo@commit" (without quotes).', "Add package", "h240")
        if IB.Result != "Cancel"
            InstallPackage(IB.Value)
    }
    LoadPackageFolder(A_WorkingDir)
    PopulateTabs()
}

PackageLVItemSelected(LV, Item, Selected) {
    if !Selected
        return
    PackageName := LV.GetText(Item, 1), Version := LV.GetText(Item, 2)

    if !g_InstalledPackages.Has(PackageName)
        return
    SelectedPackage := g_InstalledPackages[PackageName]

    Tab := g_MainGui.Tabs.Package

    if FileExist(g_MainGui.CurrentFolder g_MainGui.CurrentLibDir SelectedPackage.InstallName "\package.json") {
        Info := LoadPackageJson(g_MainGui.CurrentFolder g_MainGui.CurrentLibDir SelectedPackage.InstallName)
        Info["main"] := SelectedPackage.Main
    } else if g_Index.Has(SelectedPackage.PackageName)
        Info := g_Index[SelectedPackage.PackageName]
    else {
        Tab.Metadata.Value := "No information available about this package (missing package.json and index entry)."
        return
    }

    Tab.Metadata.Value := ExtractPackageDescription(Info)
}

IndexLVItemSelected(LV, Item, Selected) {
    if !Selected
        return
    PackageName := LV.GetText(Item, 1)
    Tab := g_MainGui.Tabs.Index
    Tab.Metadata.Value := ExtractPackageDescription(g_Index[PackageName])
    Tab.InstallBtn.Text := LV.GetText(Item, 4) = "Yes" ? "Reinstall" : "Install"
}

ExtractPackageDescription(Info) {
    Content := ""

    if Info.Has("description")
        Content .= "Description: " Info["description"] "`n"
    if Info.Has("author") {
        if (Info["author"] is String) && Info["author"]
            Content .= "Author: " Info["author"] "`n"
        else if Info["author"].Has("name")
            Content .= "Author: " Info["author"]["name"] "`n"
    }
    if Info.Has("main") {
        if (Info["main"] is String) && Info["main"]
            Content .= "Main: " Info["main"] "`n"
    }
    if Info.Has("homepage")
        Content .= "Homepage: " Info["homepage"] "`n"
    if Info.Has("license")
        Content .= "License: " Info["license"] "`n"
    if Info.Has("tags") && Info["tags"].Length {
        Content .= "Tags: "
        for Tag in Info["tags"]
            Content .= Tag ", "
        Content := SubStr(Content, 1, -2) "`n"
    }
    if Info.Has("dependencies") && Info["dependencies"].Count {
        Content .= "Dependencies:`n"
        for Dependency, Version in Info["dependencies"]
            Content .= "`t" Dependency "@" Version "`n"
    }
    return Content
}

PopulateTabs() {
    PopulatePackagesTab(g_MainGui.Tabs.Package)
    PopulateIndexTab(g_MainGui.Tabs.Index)
}

PopulatePackagesTab(Tab) {
    g_MainGui.Dependencies := Dependencies := QueryPackageDependencies()
    Tab.LV.Opt("-Redraw")
    Tab.LV.Delete()

    for PackageName, PackageInfo in g_InstalledPackages {
        VersionRange := "", InIndex := g_Index.Has(PackageName) ? "Yes" : "No"
        if Dependencies.Has(PackageName)
            VersionRange := Dependencies[PackageName].DependencyVersion
        IsInstalled := g_InstalledPackages.Has(PackageName)
        Tab.LV.Add(, PackageName, IsInstalled ? PackageInfo.InstallVersion : "", VersionRange, IsInstalled ? "Yes" : "No", InIndex)
    }
    Tab.LV.ModifyCol(1, g_InstalledPackages.Count ? unset : 100)
    Tab.LV.ModifyCol(2, 50)
    Tab.LV.ModifyCol(4, 50)
    Tab.LV.ModifyCol(5, 50)
    Tab.LV.Opt("+Redraw")
}

PopulateIndexTab(Tab) {
    g_MainGui.UnfilteredIndex := []

    Tab.LV.Opt("-Redraw")
    Tab.LV.Delete()

    for PackageName, Info in g_Index {
        if PackageName = "version"
            continue

        g_MainGui.UnfilteredIndex.Push([PackageName, g_InstalledPackages.Has(PackageName) ? g_InstalledPackages[PackageName].InstallVersion : unset, g_InstalledPackages.Has(PackageName) ? g_InstalledPackages[PackageName].DependencyVersion : unset, g_Index[PackageName]["repository"]["type"]])
        Tab.LV.Add(, g_MainGui.UnfilteredIndex[-1]*)
    }
    Tab.LV.ModifyCol(1)
    Tab.LV.ModifyCol(4, 80)
    Tab.LV.Opt("+Redraw")
}

LoadPackageFolder(FullPath) {
    FullPath := Trim(FullPath, "/\") "\"

    g_Config["last_project_directory"] := FullPath
    SaveSettings()

    SetWorkingDir(FullPath)
    RefreshWorkingDirGlobals()
    g_MainGui.CurrentFolder := FullPath
    g_MainGui.CurrentLibDir := g_LibDir "\"

    FolderTV := g_MainGui.FolderTV
    FolderTV.Opt("-Redraw")
    FolderTV.Delete()
    split := StrSplit(Trim(FullPath, "\"), "\")

    ItemID := FolderTV.Add(split[-1], 0, "Expand")
    AddSubFoldersToTree(FolderTV, FullPath, Map(), ItemID)
    FolderTV.Opt("+Redraw")
}

AddSubFoldersToTree(TV, Folder, DirList, ParentItemID := 0) {
    Loop Files, Folder "\*.*", "FD"
    {
        if A_LoopFileName ~= "^(\.git|\.vscode)$"
            continue
        ItemID := TV.Add(A_LoopFileName, ParentItemID, "Expand")
        DirList[ItemID] := A_LoopFilePath
        if DirExist(A_LoopFileFullPath)
            AddSubFoldersToTree(TV, A_LoopFileFullPath, DirList, ItemID)
    }
}

OnIndexSearch(Search, *) {
    Query := Search.Value
    Tab := g_MainGui.Tabs.Index
    LV := Tab.LV
    LV.Opt("-Redraw")
    LV.Delete()
    if Query = "" {
        for Row in g_MainGui.UnfilteredIndex
            LV.Add(, Row*)
    } else {
        if Tab.SearchByStartCB.Value {
            if Tab.SearchCaseSenseCB.Value
                CompareFunc := (v1, v2) => SubStr(v1, 1, StrLen(v2)) == v2
            else
                CompareFunc := (v1, v2) => SubStr(v1, 1, StrLen(v2)) = v2
        } else
            CompareFunc := (v1, v2) => InStr(v1, v2, Tab.SearchCaseSenseCB.Value)
        for Row in g_MainGui.UnfilteredIndex
            if CompareFunc(Row[1], Query)
                LV.Add(, Row*)
    }
    LV.Opt("+Redraw")
}

ApplyGuiConfigChanges() {
    S := g_MainGui.Tabs.Settings
    g_Config["github_token"] := S.GithubToken.Value
}

SaveSettings(ShowToolTip := false) {
    FileOpen(A_ScriptDir "\assets\config.json", "w").Write(JSON.Dump(g_Config, true))
    if (ShowToolTip) {
        ToolTip("Settings saved!")
        SetTimer ToolTip, -3000
    }
}

LaunchVersionSelectionGui(*) {
    G := Gui("+MinSize400x200 +Resize", "Package metadata")
    G.OnEvent("Size", GuiReSizer)
    I := g_MainGui.Tabs.Index
    PackageName := I.LV.GetText(Selected := I.LV.GetNext(0), 1)
    if !PackageName || Selected = 0 {
        MsgBox "No package selected"
        return
    }
    PackageInfo := InputToPackageInfo(PackageName)
    if PackageInfo.RepositoryType = "github"
        Columns := ["Release/commit", "Date", "Message"]
    else if PackageInfo.RepositoryType = "forums" {
        Columns := ["Snapshot date", "Comments"]
        if !PackageInfo.ThreadId {
            ParseRepositoryData(PackageInfo)
        }
    } else if PackageInfo.RepositoryType = "gist" {
        Columns := ["Commit", "Date"]
    } else {
        MsgBox 'This package repository is of type "' PackageInfo.RepositoryType '" for which querying version info isn`'t currently supported.'
        G.Destroy()
        return
    }
    G.LVVersions := G.Add("ListView", "w380 h200", Columns)
    G.LVVersions.X := 5, G.LVVersions.Y := 5, G.LVVersions.W := -5, G.LVVersions.H := -35
    
    G.BtnInstall := G.Add("Button", "x140", "Install selected")
    G.BtnInstall.Y := -30, G.BtnInstall.XP := 0.5, G.BtnInstall.X := -50
    G.BtnInstall.OnEvent("Click", VersionSelectionInstallBtnClicked.Bind(G, PackageName))
    G.Show("w400 h240")
    g_MainGui.Opt("+Disabled")
    G.OnEvent("Close", (*) => (g_MainGui.Opt("-Disabled"), G.Destroy()))

    PopulateVersionsLV(PackageInfo, G.LVVersions)
}

VersionSelectionInstallBtnClicked(G, PackageName, *) {
    Version := G.LVVersions.GetText(selected := G.LVVersions.GetNext(0), 1)
    if Version = "" || G.LVVersions.GetText(selected, 2) = ""
        return
    WinClose(G)
    g_MainGui.Tabs.Index.Metadata.Value := ""
    InstallPackage(PackageName "@" Version,2)
    LoadPackageFolder(A_WorkingDir)
    PopulateTabs()
}

PopulateVersionsLV(PackageInfo, LV) {
    Found := []
    if PackageInfo.RepositoryType = "github" {
        LV.ModifyCol(1, 160)
        LV.Add(, "Querying GitHub releases...")
        if (releases := QueryGitHubReleases(PackageInfo.Repository)) && (releases is Array) && releases.Length {
            Found.Push(["Releases:"])
            for release in releases
                Found.Push([release["tag_name"], release["published_at"]])
        }
        LV.Add(, "Querying GitHub commits...")
        if (commits := (IsGithubMinimalInstallPossible(PackageInfo, true) ? QueryGitHubRepo(PackageInfo.Repository, "commits?path=" (PackageInfo.Files.Length ? PackageInfo.Files[1] : PackageInfo.Main)) : QueryGitHubCommits(PackageInfo.Repository))) && commits is Array && commits.Length {
            if Found.Length
                Found.Push([""])
            Found.Push(["Commits:"])
            for commit in commits
                Found.Push([SubStr(commit["sha"], 1, 7), commit["commit"]["author"]["date"], commit["commit"]["message"]])
        }
        LV.ModifyCol(1, 100)
        LV.ModifyCol(2, 120)
        LV.Delete()
        if !Found.Length
            Found := [["No releases or commits found"]]
        for Item in Found
            LV.Add(, Item*)
        LV.ModifyCol(3)
    } else if PackageInfo.RepositoryType = "forums" {
        LV.Opt("+SortDesc")
        LV.Add(, "Querying snapshots, this may take time...")
        LV.ModifyCol(1)
        LV.ModifyCol(2, 160)
        Matches := QueryForumsReleases(PackageInfo)
        if !WinExist(LV.hwnd)
            return
        LV.Delete()
        LV.Add(, "latest", "Unversioned from live forums")
        for Match in Matches {
            LV.Add(, Match.Version, " ")
        } else
            LV.Add(, "No snapshots found in Wayback Machine")
        LV.ModifyCol(1)
    } else if PackageInfo.RepositoryType = "gist" {
        LV.Add(, "Querying Gist commits...")
        LV.ModifyCol(1)
        Gist := QueryGitHubGist(PackageInfo.Repository)
        LVItems := []
        for Info in Gist["history"] {
            LVItems.Push([SubStr(Info["version"], 1, 7), Info["committed_at"]])
        }
        LV.Delete()
        for Item in LVItems
            LV.Add(, Item*)
    }
}

LaunchModifyMetadataGui(*) {
    G := Gui("+MinSize640x480", "Package metadata")
    G.Show("w280 h300")
    G.AddText("Section h20 +0x200", "Name:")
    G.PName := G.AddEdit("yp r1 w95", g_PackageJson["name"])
    G.PName.ToolTip := WordWrap("The name of the package must be in the format Author/PackageName, where both Author and PackageName contain only URL-safe characters. For example, slashes \/ are not allowed. ")
    G.AddText("yp h20 +0x200", "Author:")
    G.PAuthor := G.AddEdit("yp w83 r1", g_PackageJson["author"] is String ? g_PackageJson["author"] : g_PackageJson["author"].Has("name") ? g_PackageJson["author"]["name"] : "")
    G.PAuthor.ToolTip := WordWrap("Full name or username of the author.")
    G.AddText("h20 xs +0x200", "Version:")
    G.PVersion := G.AddEdit("yp w87 r1", g_PackageJson["version"])
    G.PVersion.ToolTip := WordWrap("The version of the package must follow semantic versioning rules.")
    G.AddText("yp h20 +0x200", "License:")
    G.PLicense := G.AddEdit("yp w78 r1", g_PackageJson["license"])
    G.PLicense.ToolTip := WordWrap('Use a SPDX license identifier for the license you`'re using, or a string "SEE LICENSE IN <filename>", or UNLICENSED if you do not wish to grant others the right to use a private or unpublished package under any terms.')
    G.AddText("h20 xs +0x200", "Main file:")
    G.PMain := G.AddEdit("yp x75 r1 w195", g_PackageJson["main"])
    G.PMain.ToolTip := WordWrap("The main entry-point of the package which will be added to packages.ahk")
    G.AddText("h20 xs +0x200", "Description:")
    G.PDescription := G.AddEdit("yp x75 r2 w195", g_PackageJson["description"])
    G.PDescription.ToolTip := WordWrap("A short description of your package.")
    G.AddText("h20 xs +0x200", "Repository:")
    G.PRepository := G.AddEdit("yp x75 r1 w195", g_PackageJson["repository"] is String ? g_PackageJson["repository"] : g_PackageJson["repository"].Has("url") ? g_PackageJson["repository"]["url"] : "")
    G.PRepository.ToolTip := WordWrap('Where the package will be downloaded from. If omitted then the default is "Author/PackageName" which will be interpreted as a GitHub repository. This can also be a full path to a GitHub repo, or a Gist identifier, or a zip/tarball link.')
    G.AddText("h20 xs +0x200", "Keywords:")
    G.PKeywords := G.AddEdit("yp x75 r1 w195", g_PackageJson["keywords"] is Array ? ArrayJoin(g_PackageJson["keywords"], ", ") : "")
    G.PKeywords.ToolTip := WordWrap("Comma-delimited keywords that can be used to search for your package.")
    G.AddText("h20 xs +0x200", "Files:")
    G.PFiles := G.AddEdit("yp x75 r1 w195", g_PackageJson["files"])
    G.PKeywords.ToolTip := WordWrap('Comma-delimited file names, or a pattern of files such as "lib\*.ahk", or a directory, which will be included in the package if used as a dependency.')
    G.AddText("h20 xs +0x200", "Bugs:")
    G.PBugs := G.AddEdit("yp x75 r1 w195", g_PackageJson["bugs"] is Map ? (g_PackageJson["bugs"].Has("url") ? g_PackageJson["bugs"]["url"] : "") : g_PackageJson["bugs"])
    G.PBugs.ToolTip := WordWrap("The URL at which bug reports may be filed.")
    G.AddText("h20 xs +0x200", "Hover over the textboxes to see additional info.")
    G.AddButton(,"Save metadata").OnEvent("Click", SavePackageMetadata.Bind(G))
    g_MainGui.Opt("+Disabled")
    G.OnEvent("Close", (*) => (g_MainGui.Opt("-Disabled"), G.Destroy()))
    OnMessage(0x0200, On_WM_MOUSEMOVE)
}

On_WM_MOUSEMOVE(wParam, lParam, msg, Hwnd) {
    static PrevHwnd := 0, PrevTimer := 0
    if (Hwnd != PrevHwnd) {
        Text := "", ToolTip() ; Turn off any previous tooltip.
        if PrevTimer
            SetTimer PrevTimer, 0
        if CurrControl := GuiCtrlFromHwnd(Hwnd) {
            if !CurrControl.HasOwnProp("ToolTip")
                return ; No tooltip for this control.
            Text := CurrControl.ToolTip
            SetTimer (PrevTimer := (() => ToolTip(Text))), -1000
            SetTimer ToolTip, -4000 ; Remove the tooltip.
        }
        PrevHwnd := Hwnd
    }
}

SavePackageMetadata(G, *) {
    global g_PackageJson
    for Field in ["name", "version", "license", "main", "description"]
        g_PackageJson[Field] := G.P%Field%.Value

    if G.PAuthor.Value {
        if g_PackageJson["author"] is Map
            g_PackageJson["author"]["name"] := G.PAuthor.Value
        else
            g_PackageJson["author"] := G.PAuthor.Value
    }

    if G.PRepository.Value {
        if g_PackageJson["repository"] is Map
            g_PackageJson["repository"]["url"] := G.PRepository.Value
        else
            g_PackageJson["repository"] := G.PRepository.Value
    }

    if G.PKeywords.Value {
        keywords := StrSplit(G.PKeywords.Value, ",")
        for i, keyword in keywords
            keywords[i] := Trim(keyword)
        g_PackageJson["keywords"] := keywords
    }

    if G.PFiles.Value {
        files := StrSplit(G.PFiles.Value, ",")
        for i, f in files
            files[i] := Trim(f)
        g_PackageJson["files"] := files
    }

    if G.PBugs.Value {
        if g_PackageJson["bugs"] is Map
            g_PackageJson["bugs"]["url"] := G.PBugs.Value
        else
            g_PackageJson["bugs"] := G.PBugs.Value
    }
    FileOpen("package.json", "w").Write(JSON.Dump(g_PackageJson, true))
    WinClose G
}

ShowFolderTVContextMenu(FolderTV, Item, IsRightClick, *) {
    static FolderMenu
    FolderMenu := Menu()
    if Item {
        Folder := FolderTV.GetText(Item), ParentId := Item
        while ParentId := FolderTV.GetParent(ParentId)
            Folder := FolderTV.GetText(ParentId) "\" Folder
        FullPath := StrSplitLast(A_WorkingDir, "\")[1] "\" Folder
        if DirExist(FullPath)
            FolderMenu.Add("Open in Explorer", (*) => Run('explore "' FullPath '"'))
        else
            FolderMenu.Add("Edit file", (*) => Run('edit "' FullPath '"'))
    }
    FolderMenu.Add("Open project folder in Explorer", (*) => Run('explore "' A_WorkingDir '"'))
    FolderMenu.Show()
}