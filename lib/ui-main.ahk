LaunchGui(FileOrDir?, SelectedTab := 1) {
    g_MainGui.Width := 640, g_MainGui.Height := 425

    g_MainGui.OnEvent("Size", GuiReSizer)
    g_MainGui.OnEvent("Close", (*) => ExitApp())

    SB := g_MainGui.AddStatusBar(, "Undefined package")
    SB.GetPos(,,, &SB_Height) ; Get default values for StatusBar and a button to adjust for screen scaling
    g_MainGui.LoadPackageBtn := g_MainGui.AddButton(, "Load package")
    g_MainGui.LoadPackageBtn.GetPos(,,, &Btn_Height)

    g_MainGui.FolderTV := g_MainGui.Add("TreeView", "r25 w200 x10 y7", "Package files")
    g_MainGui.FolderTV.X := 10, g_MainGui.FolderTV.Height := -(SB_Height+Btn_Height+10), g_MainGui.FolderTV.WidthP := 0.3
    g_MainGui.FolderTV.OnEvent("ContextMenu", ShowFolderTVContextMenu)

    if IsSet(FileOrDir) {
        SplitPath(FileOrDir, &OutFileName:="", &OutDir:="")
        FullDirPath := OutDir
        Loop files OutDir, "D" {
            FullDirPath := A_LoopFileFullPath
            break
        }
        LoadPackageFolder(FullDirPath)
    } else
        LoadPackageFolder(FullDirPath := (g_Config.Has("last_project_directory") && DirExist(g_Config["last_project_directory"]) ? g_Config["last_project_directory"] : A_WorkingDir))

    g_MainGui.PackageJson := LoadPackageJson()

    SB.SetText(g_MainGui.PackageJson["name"] ? (g_MainGui.PackageJson["name"] "@" (g_MainGui.PackageJson["version"] || "undefined-version")) : "Undefined package: add package name and version in metadata.")
    g_MainGui.LoadPackageBtn.Y := -(SB_Height+Btn_Height+5)
    g_MainGui.ModifyMetadata := g_MainGui.AddButton("x+27", "Modify metadata")
    g_MainGui.ModifyMetadata.Anchor := g_MainGui.FolderTV, g_MainGui.ModifyMetadata.AnchorIn := false, g_MainGui.ModifyMetadata.YP := 1.0, g_MainGui.ModifyMetadata.Y := 5, g_MainGui.ModifyMetadata.XP := 1.0, g_MainGui.ModifyMetadata.X := -92
    g_MainGui.ModifyMetadata.OnEvent("Click", LaunchModifyMetadataGui)
    g_MainGui.LoadPackageBtn.OnEvent("Click", LoadPackageFromGui)

    g_MainGui.Tabs := g_MainGui.AddTab3("w410 h395 x220 y6", ["Current package", "Index", "Settings"])
    g_MainGui.Tabs.UseTab(1)
    g_MainGui.Tabs.XP := 0.30, g_MainGui.Tabs.X := 15, g_MainGui.Tabs.W := -5, g_MainGui.Tabs.H := -(SB_Height+5)

    P := g_MainGui.Tabs.Package := {TabName:"Package"}
    P.LV := g_MainGui.Add("ListView", "r10 w390 Section -Multi", ["Package name", "Version", "Allowed versions", "Installed", "Scope", "In index"])
    P.LV.W := -15
    P.LV.OnEvent("ItemSelect", PackageLVItemSelected)
    P.LV.OnEvent("ContextMenu", ShowPackageLVContextMenu)
    P.LV.TabName := "Package"
    P.ReinstallBtn := g_MainGui.AddButton("w50", "Reinstall")
    P.ReinstallBtn.OnEvent("Click", PackageAction.Bind(P, "reinstall",0,1))
    P.RemoveBtn := g_MainGui.AddButton("x+10 yp+0 w50", "Remove")
    P.RemoveBtn.OnEvent("Click", PackageAction.Bind(P, "remove",0,1))
    P.UpdateBtn := g_MainGui.AddButton("x+10 yp+0 w50", "Update")
    P.UpdateBtn.OnEvent("Click", PackageAction.Bind(P, "update",0,1))
    P.UpdateLatestBtn := g_MainGui.AddButton("x+10 yp+0", "Force update")
    P.UpdateLatestBtn.OnEvent("Click", PackageAction.Bind(P, "update-latest",,1))
    P.AddBtn := g_MainGui.AddButton("x+10 yp+0 w50", "Add")
    P.AddBtn.OnEvent("Click", PackageAction.Bind(P, "install-external",0,1))
    P.ModifyRangeBtn := g_MainGui.AddButton("x+10 yp+0 w80", "Modify range")
    P.ModifyRangeBtn.OnEvent("Click", ModifyPackageVersionRange.Bind(P.LV))
    P.Metadata := g_MainGui.Add("Edit", "xs y+10 w390 h140")
    P.Metadata.W := -15, P.Metadata.H := -(SB_Height+15)

    PopulatePackagesTab(P)

    g_MainGui.Tabs.UseTab(2)

    I := g_MainGui.Tabs.Index := {TabName:"Index"}
    I.LV := g_MainGui.Add("ListView", "r10 w390 Section -Multi", ["Package name", "Installed version", "Allowed versions", "Source"])
    I.LV.W := -15, I.LV.H := -215
    I.LV.OnEvent("ItemSelect", IndexLVItemSelected)
    I.LV.OnEvent("DoubleClick", PackageAction.Bind(I, "install",0,1))
    I.LV.OnEvent("ContextMenu", ShowPackageLVContextMenu)
    I.LV.TabName := "Index"
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
    I.InstallBtn.OnEvent("Click", PackageAction.Bind(I, "install",0,1))
    I.QueryVersionBtn := g_MainGui.AddButton("x+10 yp+0", "Query versions")
    AnchorAfter(I.QueryVersionBtn, I.InstallBtn, 5, 0)
    I.QueryVersionBtn.OnEvent("Click", LaunchVersionSelectionGui)
    I.UpdateIndexBtn := g_MainGui.AddButton("x+10 yp+0", "Update index")
    AnchorAfter(I.UpdateIndexBtn, I.QueryVersionBtn, 5, 0)
    I.UpdateIndexBtn.OnEvent("Click", UpdatePackageIndexPopulateTab)
    I.Metadata := g_MainGui.Add("Edit", "xs y+10 w390 h120 ReadOnly")
    I.Metadata.F := (this, G, *) => (I.LV.GetPos(&LVX, &LVY, &LVW, &LVH), G.GetPos(,,&GW,&GH), this.GetPos(&X, &Y, &W, &H), this.Move(LVX, NewY := LVY+LVH+60, LVW, GH-NewY-SB_Height-55))

    PopulateIndexTab(I)

    g_MainGui.Tabs.UseTab(3)

    S := g_MainGui.Tabs.Settings := {}
    g_MainGui.AddGroupBox("w200 h45 Section", "Package settings")

    g_MainGui.AddGroupBox("w195 x+10 yp+0 h90", "Path and shell")
    S.AddRemoveFromPATH := g_MainGui.AddButton("xp+20 yp+20 w150", (IsArisInPATH() ? "Remove Aris from PATH" : "Add Aris to PATH"))
    S.AddRemoveFromPATH.OnEvent("Click", (btnCtrl, *) => btnCtrl.Text = "Remove Aris from PATH" ? (RemoveArisFromPATH(), btnCtrl.Text := "Add Aris to PATH", g_Config["add_to_path"] := 0, SaveSettings()) : (AddArisToPATH(), btnCtrl.Text := "Remove Aris from PATH", g_Config["add_to_path"] := 1, SaveSettings()) )
    S.AddRemoveShellMenuItem := g_MainGui.AddButton("xp y+10 w150", (IsArisShellMenuItemPresent() ? "Remove Aris from shell" : "Add Aris to shell"))
    S.AddRemoveShellMenuItem.OnEvent("Click", (btnCtrl, *) => btnCtrl.Text = "Remove Aris from shell" ? (RemoveArisShellMenuItem(), btnCtrl.Text := "Add Aris to shell", g_Config["add_to_shell"] := 0, SaveSettings()) : (AddArisShellMenuItem(), btnCtrl.Text := "Remove Aris from shell", g_Config["add_to_shell"] := 1, SaveSettings()) )

    S.GlobalInstalls := g_MainGui.AddCheckbox("xs+10 ys+20 " (g_Config["global_install"] ? "Checked" : ""), "Install all packages globally")
    g_MainGui.AddGroupBox("xs ys+50 w200 h65", "Updates")
    S.AutoUpdateIndex := g_MainGui.AddCheckbox("xp+10 yp+20 " (g_Config["auto_update_index_daily"] ? "Checked" : ""), "Auto-update index once daily")
    S.CheckArisUpdates := g_MainGui.AddCheckbox((g_Config["check_aris_updates_daily"] ? "Checked" : ""), "Check for Aris updates daily")
   
    g_MainGui.AddGroupBox("xs w405 h50", "GitHub")
    g_MainGui.AddText("xp+10 yp+20", "Github private token:")
    S.GithubToken := g_MainGui.AddEdit("x+5 yp-3 w280 r1", g_Config["github_token"])

    S.SaveSettings := g_MainGui.AddButton("xs+150 y+20 w100", "Save settings")
    S.SaveSettings.SetFont("bold")
    S.SaveSettings.OnEvent("Click", (*) => (ApplyGuiConfigChanges(), SaveSettings(true)))

    S.Uninstall := g_MainGui.AddButton("xs+305 y+135 w100", "Uninstall Aris")
    S.Uninstall.SetFont("bold")
    S.Uninstall.OnEvent("Click", UninstallAris)

    g_MainGui.Tabs.UseTab(0)
    if SelectedTab != 1
        g_MainGui.Tabs.Choose(SelectedTab)

    g_MainGui.Move(,, g_MainGui.Width, g_MainGui.Height) ; Force draw of controls to remove flicker
    Sleep -1
    g_MainGui.Show("w" g_MainGui.Width " h" g_MainGui.Height)
    P.Metadata.Opt("+ReadOnly") ; If this isn't done after showing the GUI, the Edit may display black if the cursor was located inside of it

    Print.DefineProp("call", {call:(this, msg) => ((ctrl := ((g_MainGui.Tabs.Value = 1) ? g_MainGui.Tabs.Package.Metadata : g_MainGui.Tabs.Index.Metadata), ctrl.Value .= msg "`n", PostMessage(0x115, 7, 0,, ctrl.hWnd)))})
    if Print.Buffer
        Print(Trim(Print.Buffer)), Print.Buffer := ""

    /*
    ; This can be used to set a small identifying icon to the tray menu large icon, because by
    ; default the AHK icon is shown. However, if Aris is ran from cmd.exe then that issue isn't present.
    hIcon := DllCall("LoadImage", "ptr", 0, "str", A_ScriptDir "\assets\main.ico", "uint", 2, "int", 0, "int", 0, "uint", 0x10, "ptr")
    CLSID_TaskbarList := "{56FDF344-FD6D-11d0-958A-006097C9A090}"
    IID_ITaskbarList3 := "{EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF}"
    ITaskbarList3 := ComObject(CLSID_TaskbarList, IID_ITaskbarList3)
    ComCall(3, ITaskbarList3)
    ComCall(18, ITaskbarList3, "ptr", g_MainGui.hWnd, "ptr", hIcon, "str", "Aris")
    DllCall("CloseHandle", "ptr", hIcon)
    */

    if IsSet(OutFileName) && OutFileName {
        Print "Installing dependencies from `"" OutFileName "`"`n"
        PackageAction(P, "install-external", FileOrDir, 0)
        if FileExist("package.json") {
            Print "`n----------------------------------------------------`nInstalling packages from package.json`n"
            PackageAction(P, "install-external", "package.json", 0)
        }
    }

    if !g_Config.Has("check_aris_updates_daily") || (g_Config["check_aris_updates_daily"] && (Abs(DateDiff(A_NowUTC, g_Config["check_aris_updates_daily"], "Days")) >= 1)) {
        CheckArisUpdate()
        g_Config["check_aris_updates_daily"] := A_NowUTC
        SaveSettings()
    }
}

CheckArisUpdate() {
    Print "Checking for Aris updates..."
    if !(releases := QueryGitHubReleases("Descolada/ARIS/main")) || !(releases is Array) || !releases.Length {
        Print "Couldn't find any Aris releases"
        return
    }
    PackageJson := LoadPackageJson(A_ScriptDir)
    if VerCompare(releases[1]["tag_name"], PackageJson["version"]) <= 0 {
        Print "Aris is already up-to-date"
        return
    }
    
    if MsgBox("Aris update found. Do you wish to update to " releases[1]["tag_name"] "?", "Aris update", 0x4) != "Yes"
        return

    LoadPackageFolder(A_ScriptDir)
    UpdateWorkingDirPackage() ; This should exit the application if successful
    MsgBox "Failed to update Aris!"
}

LVGetPackageInfo(LV) {
    Selected := LV.GetNext(0)
    if !Selected
        return 0
    return {PackageName: LV.GetText(Selected, 1), Version: LV.GetText(Selected, 2), Selected: Selected}
}

PackageAction(Tab, Action, Input?, ClearOutput:=1, *) {
    Result := 1
    if Action != "install-external" {
        PackageInfo := LVGetPackageInfo(Tab.LV)
        if !PackageInfo {
            ToolTip "Select a package first!"
            SetTimer ToolTip, -3000
            return
        }
    }
    if ClearOutput
        Tab.Metadata.Value := ""
    switch Action, 0 {
        case "reinstall":
            RemovePackage(PackageInfo.PackageName "@" PackageInfo.Version, false)
            Result := InstallPackage(PackageInfo.PackageName "@" PackageInfo.Version)
        case "remove":
            if Result := RemovePackage(PackageInfo.PackageName "@" PackageInfo.Version)
                PackageInfo.Selected := Min(PackageInfo.Selected, Tab.LV.GetCount()-1)
        case "update":
            Result := InstallPackage(PackageInfo.PackageName "@" g_InstalledPackages[PackageInfo.PackageName].DependencyVersion, 1)
        case "update-latest":
            Result := InstallPackage(PackageInfo.PackageName "@latest")
        case "install":
            Result := InstallPackage(PackageInfo.PackageName)
            if !Result && g_Index.Has(PN := PackageInfo.PackageName) && g_Index[PN].Has("repository") && (Repo := g_Index[PN]["repository"] is String ? g_Index[PN]["repository"] : g_Index[PN]["repository"]["url"]) && Repo ~= "forums:|autohotkey\.com" {
                Print("`nRetrying to download latest version from AutoHotkey forums...")
                InstallPackage(PackageInfo.PackageName "@latest")
            }
        case "install-external":
            if Input && (Input is String) {
                Result := InstallPackageDependencies(Input, 0)
            } else {
                IB := InputBox('Install a package from a non-index source.`n`nInsert a source (GitHub repo, Gist, archive file URL) from where to install the package.`n`nIf installing from a GitHub repo, this can be "Username/Repo" or "Username/Repo@Version" (queries from releases) or "Username/Repo@commit" (without quotes).', "Add package", "h240")
                if IB.Result != "Cancel"
                    Result := InstallPackage(IB.Value)
            }
    }
    if Result {
        if !InStr(Action, "remove")
            OutputAddedIncludesString(!!InStr(Action, "update"))
        LoadPackageFolder(A_WorkingDir)
        PopulateTabs()
    }
    try {
        Tab.LV.Modify(PackageInfo.Selected, "Select")
        if Action = "remove" && Result
            PackageLVItemSelected(Tab.LV, PackageInfo.Selected, 1)
    }
}

ModifyPackageVersionRange(LV, *) {
    Selected := LV.GetNext(0)
    if !Selected {
        ToolTip "Select a package first!"
        SetTimer ToolTip, -3000
        return
    }
    IB := InputBox('Insert a new allowed version range for the package.`n`nPossible options:`nlatest : latest release or commit (includes major releases)`n^x.y.z : allow minor version update (y)`n~x.y.z : allow patch update (z)`n>x.y.z : greater than x.y.z`n<x.y.z : less than x.y.z`n>=x.y.z <=a.b.c : range between x.y.z and a.b.c', "Modify version range", "h240", PreviousVersion := LV.GetText(Selected, 3))
    if IB.Result != "Cancel" {
        PackageJson := LoadPackageJson()
        PackageName := LV.GetText(Selected, 1)
        PreviousValue := PackageJson["dependencies"][PackageName]
        PackageJson["dependencies"][PackageName] := InStr(PreviousValue, "@") ? StrReplace(PreviousValue, "@" PreviousVersion, "@" IB.Value) : IB.Value
        FileOpen("package.json", 0x1).Write(JSON.Dump(PackageJson, true))

        LoadPackageFolder(A_WorkingDir)
        PopulateTabs()
    }
}

PackageLVItemSelected(LV, Item, Selected) {
    if !Selected
        return
    PackageName := LV.GetText(Item, 1), Version := LV.GetText(Item, 2)

    if !g_InstalledPackages.Has(PackageName)
        return
    SelectedPackage := g_InstalledPackages[PackageName]

    Tab := g_MainGui.Tabs.Package

    if FileExist(g_MainGui.CurrentLibDir SelectedPackage.InstallName "\package.json") {
        Info := LoadPackageJson(g_MainGui.CurrentLibDir SelectedPackage.InstallName)
        if Info.Has("keywords") && IsObject(Info["keywords"])
            Info["keywords"] := ArrayJoin(Info["keywords"], ", ")
        Info["main"] := SelectedPackage.Main
    } else if g_Index.Has(SelectedPackage.PackageName)
        Info := g_Index[SelectedPackage.PackageName]
    else {
        Tab.Metadata.Value := "No information available about this package (missing package.json and index entry)."
        return
    }

    Tab.Metadata.Value := ExtractPackageDescription(Info) "`n`n#include <Aris/" SelectedPackage.PackageName "> `; " ConstructInstallCommand(SelectedPackage, SelectedPackage.InstallVersion (SelectedPackage.BuildMetadata ? "+" SelectedPackage.BuildMetadata : ""))
}

IndexLVItemSelected(LV, Item, Selected) {
    if !Selected
        return
    PackageName := LV.GetText(Item, 1)
    Tab := g_MainGui.Tabs.Index
    Tab.Metadata.Value := ExtractPackageDescription(g_Index[PackageName])
    Tab.InstallBtn.Text := LV.GetText(Item, 4) = "Yes" ? "Reinstall" : "Install"
}

UpdatePackageIndexPopulateTab(*) => (UpdatePackageIndex(), PopulateIndexTab(I))

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
        else if Info.Has("files") {
            if (Info["files"] is String) && Info["files"]
                Content .= "Main: " StrSplit(StrReplace(Info["files"], "\", "/"), "/")[-1] "`n"
            else if (Info["files"] is Array) && (Info["files"].Length = 1)
                Content .= "Main: " StrSplit(StrReplace(Info["files"][1], "\", "/"), "/")[-1]  "`n"
        }
    }
    if Info.Has("homepage")
        Content .= "Homepage: " Info["homepage"] "`n"
    if Info.Has("license")
        Content .= "License: " Info["license"] "`n"
    if Info.Has("keywords") && Info["keywords"]
        Content .= "Keywords: " Info["keywords"] "`n"
    if Info.Has("dependencies") && Info["dependencies"].Count {
        Content .= "Dependencies:`n"
        for Dependency, Version in Info["dependencies"]
            Content .= "`t" Dependency "@" Version "`n"
    }
    if Info.Has("repository") {
        if Info["repository"]["type"] = "github" {
            if InStr(Info["repository"]["url"], ":") 
                Content .= "GitHub repository: " Info["repository"]["url"]
            else {
                Split := StrSplit(Info["repository"]["url"], "/")
                Content .= "GitHub repository: https://github.com/" Split[1] "/" Split[2]
            }
        } else if Info["repository"]["type"] = "gist"
            Content .= "Gist URL: https://gist.github.com/" StrSplit(Info["repository"]["url"], "/")[1]
        else
            Content .= "Repository: " Info["repository"]["type"] ":" Info["repository"]["url"]
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
        Tab.LV.Add(, PackageName, IsInstalled ? PackageInfo.InstallVersion : "", VersionRange, IsInstalled ? "Yes" : "No", PackageInfo.Global ? "global" : "local", InIndex)
    }
    Tab.LV.ModifyCol(1, g_InstalledPackages.Count ? unset : 100)
    Tab.LV.ModifyCol(2, 50)
    Tab.LV.ModifyCol(4, 50)
    Tab.LV.ModifyCol(5, 50)
    Tab.LV.ModifyCol(6, 50)
    Tab.LV.Opt("+Redraw")
    Sleep -1
}

PopulateIndexTab(Tab) {
    g_MainGui.UnfilteredIndex := []

    Tab.LV.Opt("-Redraw")
    Tab.LV.Delete()

    for PackageName, Info in g_Index {
        if !InStr(PackageName, "/") || !IsObject(Info)
            continue

        g_MainGui.UnfilteredIndex.Push([PackageName, g_InstalledPackages.Has(PackageName) ? g_InstalledPackages[PackageName].InstallVersion : unset, g_InstalledPackages.Has(PackageName) ? g_InstalledPackages[PackageName].DependencyVersion : unset, g_Index[PackageName]["repository"]["type"]])
        Tab.LV.Add(, g_MainGui.UnfilteredIndex[-1]*)
    }
    Tab.LV.ModifyCol(1)
    Tab.LV.ModifyCol(4, 80)
    if Tab.Search.Value
        OnIndexSearch(Tab.Search)
    Tab.LV.Opt("+Redraw")
    Sleep -1
}

LoadPackageFolder(FullPath) {
    FullPath := Trim(FullPath, "/\") "\"

    PrevWorkingDir := A_WorkingDir
    try {
        SetWorkingDir(FullPath)
        RefreshWorkingDirGlobals()
        g_Config["last_project_directory"] := FullPath
        SaveSettings()
    } catch Error as err {
        Print("Failed to load package from " FullPath)
        PrintError(err, 0)
        FullPath := FullPath == PrevWorkingDir ? A_ScriptDir : PrevWorkingDir
        SetWorkingDir(FullPath)
        RefreshWorkingDirGlobals()
    }

    g_MainGui.CurrentFolder := FullPath
    g_MainGui.CurrentLibDir := g_LocalLibDir "\"

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
    StartsWithCompare := (v1) => v1 ~= (Tab.SearchCaseSenseCB.Value ? "" : "i)") "\b\Q" Query "\E"
    SubstrCompare := (v1) => InStr(v1, Query, Tab.SearchCaseSenseCB.Value)
    if Query = "" {
        for Row in g_MainGui.UnfilteredIndex
            LV.Add(, Row*)
    } else {
        if Tab.SearchByStartCB.Value {
            CompareFunc := StartsWithCompare
            FilteredIndex := []
            for Row in g_MainGui.UnfilteredIndex
                if CompareFunc(Row[1])
                    FilteredIndex.Push(Row)
        } else {
            FilteredIndex := []
            for Row in g_MainGui.UnfilteredIndex {
                PackageName := Row[1], IndexEntry := g_Index[PackageName]
                if StartsWithCompare(StrSplit(PackageName, "/",, 2)[-1]) {
                    Row.Weight := 10000, FilteredIndex.Push(Row)
                } else if StartsWithCompare(PackageName) {
                    Row.Weight := 1000, FilteredIndex.Push(Row)
                } else if SubStrCompare(PackageName) {
                    Row.Weight := 100, FilteredIndex.Push(Row)
                } else if IndexEntry.Has("keywords") && StartsWithCompare(IndexEntry["keywords"]) {
                    Row.Weight := 10, FilteredIndex.Push(Row)
                } else if IndexEntry.Has("description") && StartsWithCompare(IndexEntry["description"]) {
                    Row.Weight := 1, FilteredIndex.Push(Row)
                } else
                    Row.Weight := 0
            }
            FilteredIndex := ObjectSort(FilteredIndex, "Weight",, true)
        }

        for Row in FilteredIndex
            LV.Add(, Row*)
    }
    LV.Opt("+Redraw")
}

ApplyGuiConfigChanges() {
    S := g_MainGui.Tabs.Settings
    g_Config["github_token"] := S.GithubToken.Value
    g_Switches["global_install"] := g_Config["global_install"] := S.GlobalInstalls.Value
    g_Config["auto_update_index_daily"] := S.AutoUpdateIndex.Value ? g_Config["auto_update_index_daily"] || 20240101000000 : 0
    g_Config["check_aris_updates_daily"] := S.CheckArisUpdates.Value ? g_Config["check_aris_updates_daily"] || 20240101000000 : 0
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
    OutputAddedIncludesString()
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
        if (commits := ((CommitsPath := GetPathForGitHubCommits(PackageInfo.Files)) != "" ? QueryGitHubRepo(PackageInfo.Repository, "commits?per_page=100&path=" CommitsPath) : QueryGitHubCommits(PackageInfo.Repository))) && commits is Array && commits.Length {
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
    G.PFiles.ToolTip := WordWrap('Comma-delimited file names, or a pattern of files such as "lib\*.ahk", or a directory, which will be included in the package if used as a dependency.')
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

LoadPackageFromGui(*) {
    dir := DirSelect("*" g_MainGui.CurrentFolder)
    if !dir
        return
    g_MainGui.Tabs.Index.Metadata.Value := ""
    g_MainGui.Tabs.Package.Metadata.Value := ""
    
    LoadPackageFolder(dir)
    PopulateTabs()
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

ShowPackageLVContextMenu(LV, Item, IsRightClick, *) {
    Tab := LV.TabName = "Index" ? g_MainGui.Tabs.Index : g_MainGui.Tabs.Package
    PackageMenu := Menu()
    if !(Item && (PackageName := LV.GetText(Item))) {
        if LV.TabName = "Index" {
            PackageMenu.Add("Update index", UpdatePackageIndexPopulateTab)
        } else {
            PackageMenu.Add("Install external package", PackageAction.Bind(Tab, "install-external",0,1))
        }
    } else {
        if g_InstalledPackages.Has(PackageName) {
            PackageMenu.Add("Modify version range", ModifyPackageVersionRange.Bind(LV))
            PackageMenu.Add("Update", PackageAction.Bind(Tab, "update",0, 1))
            PackageMenu.Add("Force update to latest", PackageAction.Bind(Tab, "update-latest",, 1))
            PackageMenu.Add("Reinstall", PackageAction.Bind(Tab, "reinstall",0, 1))
            PackageMenu.Add("Remove", PackageAction.Bind(Tab, "remove",0, 1))
        } else {
            PackageMenu.Add("Install", PackageAction.Bind(Tab, "install",0, 1))
            PackageMenu.Add("Query versions", LaunchVersionSelectionGui)
        }
    }
    PackageMenu.Show()
}

UninstallAris(*) {
    if MsgBox("This action will delete the current folder Aris is running in, and remove any shell and PATH entries.`n`nAre you sure you want to continue?", "Warning", 0x4|0x30) = "No"
        return
    RemoveArisFromPATH()
    RemoveArisShellMenuItem()
    try DirDelete(A_ScriptDir, 1)
    if !FileExist(A_ScriptFullPath) {
        MsgBox("Aris successfully uninstalled.", "Aris", 0x40)
        ExitApp
    } else
        MsgBox("Failed to delete the Aris folder. Delete the main folder manually to uninstall.", "Aris", 0x10)
}