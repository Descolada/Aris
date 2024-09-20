global NapGui := Gui("+MinSize640x480", "NAP")

LaunchGui() {

    WriteStdOut.DefineProp("call", {call:(this, msg) => NapGui.Tabs.Value = 1 ? NapGui.Tabs.Package.Metadata.Value .= msg "`n" : NapGui.Tabs.Index.Metadata.Value .= msg "`n"})
    
    NapGui.OnEvent("Close", (*) => ExitApp())

    NapGui.FolderTV := NapGui.Add("TreeView", "r25 w200", "Package files")

    NapGui.PackageJson := LoadPackageJson()
    NapGui.AddStatusBar(, NapGui.PackageJson["name"] "@" NapGui.PackageJson["version"])
    NapGui.LoadPackageBtn := NapGui.AddButton(, "Load package")
    NapGui.ModifyMetadata := NapGui.AddButton("x+27", "Modify metadata")
    NapGui.ModifyMetadata.OnEvent("Click", LaunchModifyMetadataGui)
    NapGui.LoadPackageBtn.OnEvent("Click", (*) => (dir := DirSelect("*" NapGui.CurrentFolder), dir ? LoadPackageFolder(dir) : ""))

    NapGui.Tabs := NapGui.AddTab3("w410 h395 x220 y6", ["Current package", "Index", "Settings"])
    NapGui.Tabs.UseTab(1)

    P := NapGui.Tabs.Package := {}
    P.LV := NapGui.Add("ListView", "r10 w390 Section -Multi", ["Package name", "Version", "Allowed versions", "Installed", "In index"])
    P.LV.OnEvent("ItemSelect", PackageLVItemSelected)
    P.ReinstallBtn := NapGui.AddButton(, "Reinstall")
    P.ReinstallBtn.OnEvent("Click", PackageAction.Bind("reinstall"))
    P.RemoveBtn := NapGui.AddButton("x+10 yp+0", "Remove")
    P.RemoveBtn.OnEvent("Click", PackageAction.Bind("remove"))
    P.UpdateBtn := NapGui.AddButton("x+10 yp+0", "Update")
    P.UpdateBtn.OnEvent("Click", PackageAction.Bind("update"))
    P.AddBtn := NapGui.AddButton("x+10 yp+0", "Add")
    P.AddBtn.OnEvent("Click", PackageAction.Bind("install"))
    P.Metadata := NapGui.Add("Edit", "xs y+10 w390 h140 ReadOnly")

    PopulatePackagesTab(P)

    NapGui.Tabs.UseTab(2)

    I := NapGui.Tabs.Index := {}
    I.LV := NapGui.Add("ListView", "r10 w390 Section -Multi", ["Package name", "Compatible version", "Latest version", "Installed"])
    I.LV.OnEvent("ItemSelect", IndexLVItemSelected)
    NapGui.Add("Text",, "Search:")
    I.Search := NapGui.Add("Edit", "x+5 yp-2 -Multi")
    I.Search.OnEvent("Change", OnIndexSearch)
    I.SearchByStartCB := NapGui.Add("Checkbox", "x+10 yp+4", "Match start")
    I.SearchByStartCB.OnEvent("Click", (*) => OnIndexSearch(I.Search))
    I.SearchCaseSenseCB := NapGui.Add("Checkbox", "x+5 yp", "Match case")
    I.SearchCaseSenseCB.OnEvent("Click", (*) => OnIndexSearch(I.Search))

    I.InstallBtn := NapGui.AddButton("xs y+8 w60", "Install")
    I.InstallBtn.OnEvent("Click", (*) => (NapGui.Tabs.Index.Metadata.Value := "", PackageInfo := LVGetPackageInfo(NapGui.Tabs.Index.LV), InstallPackage(PackageInfo.PackageName), PopulateTabs()))
    I.QueryVersionBtn := NapGui.AddButton("x+10 yp+0", "Query versions")
    I.UpdateIndexBtn := NapGui.AddButton("x+10 yp+0", "Update index")
    I.Metadata := NapGui.Add("Edit", "xs y+10 w390 h120 ReadOnly")

    PopulateIndexTab(I)

    NapGui.Tabs.UseTab(3)

    NapGui.AddText("Section", "Github private token:")
    S := NapGui.Tabs.Settings := {}
    S.GithubToken := NapGui.AddEdit("x+5 yp-3 w280 r1", g_Config.Has("github_token") ? g_Config["github_token"] : "")
    S.SaveSettings := NapGui.AddButton("xs y+5", "Save settings")
    S.SaveSettings.OnEvent("Click", SaveSettings)

    NapGui.Tabs.UseTab(0)

    LoadPackageFolder(A_WorkingDir)

    NapGui.Show("w640 h425")
    WinRedraw(NapGui) ; Prevents the edit box from sometimes being black
}

LVGetPackageInfo(LV) {
    Selected := LV.GetNext(0)
    if !Selected
        return 0
    return {PackageName: LV.GetText(Selected, 1), Version: LV.GetText(Selected, 2)}
}

PackageAction(Action, Btn, *) {
    if Action != "install" {
        PackageInfo := LVGetPackageInfo(NapGui.Tabs.Package.LV)
        if !PackageInfo
            return
    }
    NapGui.Tabs.Package.Metadata.Value := ""
    switch Action, 0 {
        case "reinstall":
            RemovePackage(PackageInfo.PackageName "@" PackageInfo.Version)
            InstallPackage(PackageInfo.PackageName "@" PackageInfo.Version)
        case "remove":
            RemovePackage(PackageInfo.PackageName "@" PackageInfo.Version)
        case "update":
            InstallPackage(PackageInfo.PackageName "@" PackageInfo.Version,, true)
        case "install":
            IB := InputBox('Install a package from a non-index source.`n`nInsert a source (GitHub repo, Gist, archive file URL) from where to install the package.`n`nIf installing from a GitHub repo, this can be "Username/Repo" or "Username/Repo@Version" (queries from releases) or "Username/Repo@commit" (without quotes).', "Add package", "h240")
        if IB.Result != "Cancel"
            InstallPackage(IB.Value)
    }
    PopulateTabs()
    LoadPackageFolder(A_WorkingDir)
}

PackageLVItemSelected(LV, Item, Selected) {
    if !Selected
        return
    PackageName := LV.GetText(Item, 1), Version := LV.GetText(Item, 2)

    Installed := NapGui.InstalledPackages
    if !Installed.Has(PackageName)
        return
    SelectedPackage := Installed[PackageName]

    Tab := NapGui.Tabs.Package

    if FileExist(NapGui.CurrentFolder NapGui.CurrentLibDir SelectedPackage.InstallName "\package.json")
        Info := LoadPackageJson(NapGui.CurrentFolder NapGui.CurrentLibDir SelectedPackage.InstallName)
    else if g_Index.Has(SelectedPackage.PackageName)
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
    Tab := NapGui.Tabs.Index
    Tab.Metadata.Value := ExtractPackageDescription(g_Index[PackageName])
    Tab.InstallBtn.Text := LV.GetText(Item, 4) = "Yes" ? "Reinstall" : "Install"
}

ExtractPackageDescription(Info) {
    Content := ""

    if Info.Has("description")
        Content .= "Description: " Info["description"] "`n"
    if Info.Has("author") {
        if Info["author"] is String
            Content .= "Author: " Info["author"] "`n"
        else if Info["author"].Has("name")
            Content .= "Author: " Info["author"]["name"] "`n"
    }
    if Info.Has("main") {
        if Info["main"] is String
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
    PopulatePackagesTab(NapGui.Tabs.Package)
    PopulatePackagesTab(NapGui.Tabs.Index)
}

PopulatePackagesTab(Tab) {
    NapGui.InstalledPackages := Installed := ParseInstalledPackages()
    NapGui.Dependencies := Dependencies := GetPackageDependencies()
    Tab.LV.Opt("-Redraw")
    Tab.LV.Delete()

    for PackageName, Version in Dependencies {
        VersionRange := "", InIndex := g_Index.Has(PackageName) ? "Yes" : "No"
        if Dependencies.Has(PackageName)
            VersionRange := g_PackageJson["dependencies"][PackageName]
        IsInstalled := Installed.Has(PackageName)
        Tab.LV.Add(, PackageName, IsInstalled ? Version : "", VersionRange, IsInstalled ? "Yes" : "No", InIndex)
    }
    Tab.LV.ModifyCol(1, Installed.Count ? unset : 100)
    Tab.LV.ModifyCol(2, 50)
    Tab.LV.ModifyCol(4, 50)
    Tab.LV.ModifyCol(5, 50)
    Tab.LV.Opt("+Redraw")
}

PopulateIndexTab(Tab) {
    Installed := NapGui.InstalledPackages
    NapGui.UnfilteredIndex := []

    Tab.LV.Opt("-Redraw")
    Tab.LV.Delete()

    for PackageName, Info in g_Index {
        if PackageName = "version"
            continue

        NapGui.UnfilteredIndex.Push([PackageName,,, Installed.Has(PackageName) ? "Yes" : "No"])
        Tab.LV.Add(, NapGui.UnfilteredIndex[-1]*)
    }
    Tab.LV.ModifyCol(1)
    Tab.LV.ModifyCol(4, 50)
    Tab.LV.Opt("+Redraw")
}

LoadPackageFolder(FullPath) {
    FullPath := Trim(FullPath, "/\") "\"
    NapGui.CurrentFolder := FullPath
    NapGui.CurrentLibDir := FindLibDir(NapGui.CurrentFolder) "\"
    SetWorkingDir(FullPath)
    global g_PackageJson := LoadPackageJson()

    FolderTV := NapGui.FolderTV
    FolderTV.Opt("-Redraw")
    FolderTV.Delete()
    split := StrSplit(FullPath, "\")

    AddSubFoldersToTree(FolderTV, FullPath, Map())
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
    Tab := NapGui.Tabs.Index
    LV := Tab.LV
    LV.Opt("-Redraw")
    LV.Delete()
    if Query = "" {
        for Row in NapGui.UnfilteredIndex
            LV.Add(, Row*)
    } else {
        if Tab.SearchByStartCB.Value {
            if Tab.SearchCaseSenseCB.Value
                CompareFunc := (v1, v2) => SubStr(v1, 1, StrLen(v2)) == v2
            else
                CompareFunc := (v1, v2) => SubStr(v1, 1, StrLen(v2)) = v2
        } else
            CompareFunc := (v1, v2) => InStr(v1, v2, Tab.SearchCaseSenseCB.Value)
        for Row in NapGui.UnfilteredIndex
            if CompareFunc(Row[1], Query)
                LV.Add(, Row*)
    }
    LV.Opt("+Redraw")
}

SaveSettings(*) {
    S := NapGui.Tabs.Settings
    g_Config["github_token"] := S.GithubToken.Value
    FileOpen(A_ScriptDir "\assets\config.json", "w").Write(JSON.Dump(g_Config, true))
    ToolTip("Settings saved!")
    SetTimer ToolTip, -3000
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
    G.PBugs := G.AddEdit("yp x75 r1 w195", g_PackageJson["bugs"].Has("url") ? g_PackageJson["bugs"]["url"] : "")
    G.PBugs.ToolTip := WordWrap("The URL at which bug reports may be filed.")
    G.AddText("h20 xs +0x200", "Hover over the textboxes to see additional info.")
    G.AddButton(,"Save metadata").OnEvent("Click", SavePackageMetadata.Bind(G))
    NapGui.Opt("+Disabled")
    G.OnEvent("Close", (*) => (NapGui.Opt("-Disabled"), G.Destroy()))
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