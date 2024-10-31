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
    }
}

RemoveArisFromPATH() {
    if !(g_LocalAppData)
        return

    CurrPath := g_IsComSpecAvailable ? RunCMD(A_ComSpec . " /c " 'reg query HKCU\Environment /v PATH') : RegRead("HKCU\Environment", "PATH")
    CurrPath := RegExReplace(CurrPath, "^[\w\W]*?PATH\s+REG_SZ\s+",,,1)

    Global G_RunCMD
    if g_IsComSpecAvailable && G_RunCMD.ExitCode
        return

    if InStr(CurrPath, ";" g_LocalAppData "\Programs\Aris") {
        g_IsComSpecAvailable ? RunWait(A_ComSpec ' /c SETX PATH "' StrReplace(CurrPath, ";" g_LocalAppData "\Programs\Aris") '"',, "Hide") : RegWrite(StrReplace(CurrPath, ";" g_LocalAppData "\Programs\Aris"), "REG_SZ", "HKCU\Environment", "PATH")
    }
    if FileExist(g_LocalAppData "\Programs\Aris\Aris.bat") {
        DirDelete(g_LocalAppData "\Programs\Aris", true)
    }
}

IsArisInPATH() {
    if !(g_LocalAppData)
        return false
    CurrPath := RegRead("HKCU\Environment", "PATH", "")
    CurrPath := RegExReplace(CurrPath, "^[\w\W]*?PATH\s+REG_SZ\s+",,,1)
    if !CurrPath || !InStr(CurrPath, g_LocalAppData "\Programs\Aris")
        return false
    if !FileExist(g_LocalAppData "\Programs\Aris\Aris.bat") || !InStr(FileRead(g_LocalAppData "\Programs\Aris\Aris.bat"), A_AhkPath)
        return false
    return true
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
        Current := RegRead(GetArisShellRegistryKey() "\Shell\Aris\command")
        if !Current || !InStr(Current, A_AhkPath) || !InStr(Current, A_ScriptDir)
            return 0
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