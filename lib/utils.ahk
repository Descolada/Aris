class Mapi extends Map {
    CaseSense := "Off"
}

WordWrap(str, column:=56, indentChar:="") {
    if !IsInteger(column)
        throw TypeError("WordWrap: argument 'column' must be an integer", -1)
    out := ""
    indentLength := StrLen(indentChar)

    Loop parse, str, "`n", "`r" {
        if (StrLen(A_LoopField) > column) {
            pos := 1
            Loop parse, A_LoopField, " "
                if (pos + (LoopLength := StrLen(A_LoopField)) <= column)
                    out .= (A_Index = 1 ? "" : " ") A_LoopField
                    , pos += LoopLength + 1
                else
                    pos := LoopLength + 1 + indentLength
                    , out .= "`n" indentChar A_LoopField

            out .= "`n"
        } else
            out .= A_LoopField "`n"
    }
    return SubStr(out, 1, -1)
}

StrSplitLast(str, delim) => (pos := InStr(str, delim,,-1)) ? [SubStr(str, 1, pos-1), SubStr(str, pos+StrLen(delim))] : [str]

ArrayJoin(arr, delim:=",") {
    result := ""
    for v in arr
        result .= (v ?? "") delim
    return (len := StrLen(delim)) ? SubStr(result, 1, -len) : result
}

/*
 * ObjectSort() by bichlepa
 * 
 * Description:
 *    Reads content of an object and returns a sorted array
 * 
 * Parameters:
 *    obj:              Object which will be sorted
 *    keyName:          [optional] 
 *                      Omit it if you want to sort an array of strings, numbers etc.
 *                      If you have an array of objects, specify here the key by which contents the object will be sorted.
 *    callBackFunction: [optional] Use it if you want to have custom sort rules.
 *                      The function will be called once for each value. It must return a number or string.
 *    reverse:          [optional] Pass true if the result array should be reversed
 */
ObjectSort(obj, keyName := "", callbackFunc := "", reverse := false) {
    temp := Map()
    sorted := [] ; Return value
    
    for oneKey, oneValue in (((obj is Map) || (obj is Array)) ? obj : obj.OwnProps()) {
        ; Get the value by which it will be sorted
        if keyName
            value := oneValue is Map ? oneValue[keyName] : oneValue.%keyName%
        else
            value := oneValue
        
        ; If there is a callback function, call it. The value is the key of the temporary list.
        if (callbackFunc)
            tempKey := callbackFunc(value)
        else
            tempKey := value
        
        ; Insert the value in the temporary object.
        ; It may happen that some values are equal therefore we put the values in an array.
        if !temp.Has(tempKey)
            temp[tempKey] := []
        temp[tempKey].Push(oneValue)
    }
    
    ; Now loop through the temporary list. AutoHotkey sorts them for us.
    for oneTempKey, oneValueList in temp {
        for oneValueIndex, oneValue in oneValueList {
            ; And add the values to the result list
            if (reverse)
                sorted.InsertAt(1, oneValue)
            else
                sorted.Push(oneValue)
        }
    }
    
    return sorted
}

; Credit: iPhilip, Source: https://www.autohotkey.com/boards/viewtopic.php?style=17&p=509167#p509167
; https://en.wikipedia.org/wiki/Levenshtein_distance#Iterative_with_two_matrix_rows
LD(Source, Target, CaseSense := True) {
    if CaseSense ? Source == Target : Source = Target
       return 0
    Source := StrSplit(Source)
    Target := StrSplit(Target)
    if !Source.Length
       return Target.Length
    if !Target.Length
       return Source.Length
    
    v0 := [], v1 := []
    Loop Target.Length + 1
       v0.Push(A_Index - 1)
    v1.Length := v0.Length
    
    for Index, SourceChar in Source {
       v1[1] := Index
       for TargetChar in Target
          v1[A_Index + 1] := Min(v1[A_Index] + 1, v0[A_Index + 1] + 1, v0[A_Index] + (CaseSense ? SourceChar !== TargetChar : SourceChar != TargetChar))
       Loop Target.Length + 1
          v0[A_Index] := v1[A_Index]
    }
    return v1[Target.Length + 1]
}

ConvertRange(OldValue, OldMin, OldMax, NewMin, NewMax) => (((OldValue - OldMin) * (NewMax - NewMin)) / (OldMax - OldMin)) + NewMin

MoveFilesAndFolders(SourcePattern, DestinationFolder, DoOverwrite := false) {
    if DoOverwrite = 1
        DoOverwrite := 2  ; See DirMove for description of mode 2 vs. 1.
    ; First move all the files (but not the folders):
    FileMove SourcePattern, DestinationFolder, DoOverwrite
    ; Now move all the folders:
    Loop Files, SourcePattern, "D"  ; D means "retrieve folders only".
        DirMove A_LoopFilePath, DestinationFolder "\" A_LoopFileName, DoOverwrite
}

DirCreateEx(FullPath) {
    Dir := ""
    for Path in StrSplit(FullPath, "\") {
        Dir := (Dir ? Dir "\" : "") Path
        if !DirExist(Dir)
            DirCreate(Dir)
    }
}

RegExMatchAll(haystack, needleRegEx, startingPosition := 1) {
	out := [], end := StrLen(haystack)+1
	While startingPosition < end && RegExMatch(haystack, needleRegEx, &outputVar, startingPosition)
		out.Push(outputVar), startingPosition := outputVar.Pos + (outputVar.Len || 1)
	return out
}

; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=74647
RunCMD(P_CmdLine, P_WorkingDir := "", P_Codepage := "CP0", P_Func := 0, P_Slow := 1)
{
;  RunCMD Temp_v0.99 for ah2 By SKAN on D532/D67D @ autohotkey.com/r/?p=448912

    Global G_RunCMD

    If  Not IsSet(G_RunCMD)
        G_RunCMD := {}

    G_RunCMD                     :=  {PID: 0, ExitCode: ""}

    Local  CRLF                  :=  Chr(13) Chr(10)
        ,  hPipeR                :=  0
        ,  hPipeW                :=  0
        ,  PIPE_NOWAIT           :=  1
        ,  HANDLE_FLAG_INHERIT   :=  1
        ,  dwMask                :=  HANDLE_FLAG_INHERIT
        ,  dwFlags               :=  HANDLE_FLAG_INHERIT

    DllCall("Kernel32\CreatePipe", "ptrp",&hPipeR, "ptrp",&hPipeW, "ptr",0, "int",0)
  , DllCall("Kernel32\SetHandleInformation", "ptr",hPipeW, "int",dwMask, "int",dwFlags)
  , DllCall("Kernel32\SetNamedPipeHandleState", "ptr",hPipeR, "uintp",PIPE_NOWAIT, "ptr",0, "ptr",0)

    Local  B_OK                  :=  0
        ,  P8                    :=  A_PtrSize=8
        ,  STARTF_USESTDHANDLES  :=  0x100
        ,  STARTUPINFO
        ,  PROCESS_INFORMATION

    PROCESS_INFORMATION          :=  Buffer(P8 ?  24 : 16, 0)                  ;  PROCESS_INFORMATION
  , STARTUPINFO                  :=  Buffer(P8 ? 104 : 68, 0)                  ;  STARTUPINFO

  , NumPut("uint", P8 ? 104 : 68, STARTUPINFO)                                 ;  STARTUPINFO.cb
  , NumPut("uint", STARTF_USESTDHANDLES, STARTUPINFO, P8 ? 60 : 44)            ;  STARTUPINFO.dwFlags
  , NumPut("ptr",  hPipeW, STARTUPINFO, P8 ? 88 : 60)                          ;  STARTUPINFO.hStdOutput
  , NumPut("ptr",  hPipeW, STARTUPINFO, P8 ? 96 : 64)                          ;  STARTUPINFO.hStdError

    Local  CREATE_NO_WINDOW      :=  0x08000000
        ,  PRIORITY_CLASS        :=  DllCall("Kernel32\GetPriorityClass", "ptr",-1, "uint")

    B_OK :=  DllCall( "Kernel32\CreateProcessW"
                    , "ptr", 0                                                 ;  lpApplicationName
                    , "ptr", StrPtr(P_CmdLine)                                 ;  lpCommandLine
                    , "ptr", 0                                                 ;  lpProcessAttributes
                    , "ptr", 0                                                 ;  lpThreadAttributes
                    , "int", True                                              ;  bInheritHandles
                    , "int", CREATE_NO_WINDOW | PRIORITY_CLASS                 ;  dwCreationFlags
                    , "int", 0                                                 ;  lpEnvironment
                    , "ptr", DirExist(P_WorkingDir) ? StrPtr(P_WorkingDir) : 0 ;  lpCurrentDirectory
                    , "ptr", STARTUPINFO                                       ;  lpStartupInfo
                    , "ptr", PROCESS_INFORMATION                               ;  lpProcessInformation
                    , "uint"
                    )

    DllCall("Kernel32\CloseHandle", "ptr",hPipeW)

    If  Not B_OK
        Return ( DllCall("Kernel32\CloseHandle", "ptr",hPipeR), "" )

    G_RunCMD.PID := NumGet(PROCESS_INFORMATION, P8 ? 16 : 8, "uint")

    Local  FileObj
        ,  Line                  :=  ""
        ,  LineNum               :=  1
        ,  sOutput               :=  ""
        ,  ExitCode              :=  0

    FileObj  :=  FileOpen(hPipeR, "h", P_Codepage)
  , P_Slow   :=  !! P_Slow

    Sleep_() =>  (Sleep(P_Slow), G_RunCMD.PID)

    While   DllCall("Kernel32\PeekNamedPipe", "ptr",hPipeR, "ptr",0, "int",0, "ptr",0, "ptr",0, "ptr",0)
      and   Sleep_()
            While  G_RunCMD.PID and not FileObj.AtEOF
                   Line           :=  FileObj.ReadLine()
                ,  sOutput        .=  StrLen(Line)=0 and FileObj.Pos=0
                                   ?  ""
                                   :  (
                                         P_Func
                                      ?  P_Func.Call(Line CRLF, LineNum++)
                                      :  Line CRLF
                                      )

    hProcess                     :=  NumGet(PROCESS_INFORMATION, 0, "ptr")
  , hThread                      :=  NumGet(PROCESS_INFORMATION, A_PtrSize, "ptr")

  , DllCall("Kernel32\GetExitCodeProcess", "ptr",hProcess, "ptrp",&ExitCode)
  , DllCall("Kernel32\CloseHandle", "ptr",hProcess)
  , DllCall("Kernel32\CloseHandle", "ptr",hThread)
  , DllCall("Kernel32\CloseHandle", "ptr",hPipeR)
  , G_RunCMD := {PID: 0, ExitCode: ExitCode}

    Return RTrim(sOutput, CRLF)
}

ExecScript(Script, args:="") {
    shell := ComObject("WScript.Shell")
    exec := shell.Exec('"' A_AhkPath '" /ErrorStdOut * ' args)
    exec.StdIn.Write(Script)
    exec.StdIn.Close()
    return {Output:exec.StdOut.ReadAll(), ExitCode:exec.ExitCode}
}

QuoteFile(name) => InStr(name, " ") ? '"' name '"' : name

RemoveAhkSuffix(name) => RegExReplace(name, "\.ahk?\d?(?=$|@)")

FindMatchingAssets(needle, assetArray) {
    if !InStr(needle, ".")
        throw ValueError("The needle must contain at least one . character", -1, needle)
    matches := []
    if !InStr(needle, "*") { ; No wildcard, try to find partial match
        for k, v in assetArray {
            if InStr(v["name"], needle)
                matches.Push(v)
        }
    } else { ; Wildcard present
        ; Escape legal file name characters with RegEx meanings
        needle := RegExReplace(needle, "[\\\.\^\$\+\{\}\[\]\(\)\``]", "\$0")
        needle := StrReplace("^" needle "$","*",".*") ; Replace the wildcard
        for k, v in assetArray {
            if RegExMatch(v["name"], needle, &found:="") && found[0]
                matches.push(v)
        }
    }
    return matches
}