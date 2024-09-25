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

; HashFile by Deo
; https://autohotkey.com/board/topic/66139-ahk-l-calculating-md5sha-checksum-from-file/
; Modified for AutoHotkey v2 by lexikos.

/*
HASH types:
1 - MD2
2 - MD5
3 - SHA
4 - SHA256
5 - SHA384
6 - SHA512
*/
HashFile(filePath, hashType:=2)
{
	static PROV_RSA_AES := 24
	static CRYPT_VERIFYCONTEXT := 0xF0000000
	static BUFF_SIZE := 1024 * 1024 ; 1 MB
	static HP_HASHVAL := 0x0002
	static HP_HASHSIZE := 0x0004
	
    switch hashType {
        case 1: hash_alg := (CALG_MD2 := 32769)
        case 2: hash_alg := (CALG_MD5 := 32771)
        case 3: hash_alg := (CALG_SHA := 32772)
        case 4: hash_alg := (CALG_SHA_256 := 32780)
        case 5: hash_alg := (CALG_SHA_384 := 32781)
        case 6: hash_alg := (CALG_SHA_512 := 32782)
        default: throw ValueError('Invalid hashType', -1, hashType)
    }
	
	f := FileOpen(filePath, "r")
    f.Pos := 0 ; Rewind in case of BOM.
    
    HCRYPTPROV() => {
        ptr: 0,
        __delete: this => this.ptr && DllCall("Advapi32\CryptReleaseContext", "Ptr", this, "UInt", 0)
    }
    
	if !DllCall("Advapi32\CryptAcquireContextW"
				, "Ptr*", hProv := HCRYPTPROV()
				, "Uint", 0
				, "Uint", 0
				, "Uint", PROV_RSA_AES
				, "UInt", CRYPT_VERIFYCONTEXT)
		throw OSError()
	
    HCRYPTHASH() => {
        ptr: 0,
        __delete: this => this.ptr && DllCall("Advapi32\CryptDestroyHash", "Ptr", this)
    }
    
	if !DllCall("Advapi32\CryptCreateHash"
				, "Ptr", hProv
				, "Uint", hash_alg
				, "Uint", 0
				, "Uint", 0
				, "Ptr*", hHash := HCRYPTHASH())
        throw OSError()
	
	read_buf := Buffer(BUFF_SIZE, 0)
	
	While (cbCount := f.RawRead(read_buf, BUFF_SIZE))
	{
		if !DllCall("Advapi32\CryptHashData"
					, "Ptr", hHash
					, "Ptr", read_buf
					, "Uint", cbCount
					, "Uint", 0)
			throw OSError()
	}
	
	if !DllCall("Advapi32\CryptGetHashParam"
				, "Ptr", hHash
				, "Uint", HP_HASHSIZE
				, "Uint*", &HashLen := 0
				, "Uint*", &HashLenSize := 4
				, "UInt", 0) 
        throw OSError()
		
    bHash := Buffer(HashLen, 0)
	if !DllCall("Advapi32\CryptGetHashParam"
				, "Ptr", hHash
				, "Uint", HP_HASHVAL
				, "Ptr", bHash
				, "Uint*", &HashLen
				, "UInt", 0 )
        throw OSError()
	
	loop HashLen
		HashVal .= Format('{:02x}', (NumGet(bHash, A_Index-1, "UChar")) & 0xff)
	
	return HashVal
}

ObjToQuery(oData) { ; https://gist.github.com/anonymous1184/e6062286ac7f4c35b612d3a53535cc2a?permalink_comment_id=4475887#file-winhttprequest-ahk
    static HTMLFile := InitHTMLFile()
    if (!IsObject(oData)) {
        return oData
    }
    out := ""
    for key, val in (oData is Map ? oData : oData.OwnProps()) {
        out .= HTMLFile.parentWindow.encodeURIComponent(key) "="
        out .= HTMLFile.parentWindow.encodeURIComponent(val) "&"
    }
    return "?" RTrim(out, "&")
}

InitHTMLFile() {
    doc := ComObject("HTMLFile")
    doc.write("<meta http-equiv='X-UA-Compatible' content='IE=Edge'>")
    return doc
}

EncodeDecodeURI(str, encode := true) {
    VarSetStrCapacity(&result:="", pcchEscaped:=500)
    if encode {
        DllCall("Shlwapi.dll\UrlEscape", "str", str, "ptr", StrPtr(result), "uint*", &pcchEscaped, "uint", 0x00080000 | 0x00002000)
    } else {
        DllCall("Shlwapi.dll\UrlUnescape", "str", str, "ptr", StrPtr(result), "uint*", &pcchEscaped, "uint", 0x10000000)
    }
    VarSetStrCapacity(&result, -1)
    return result
}

DownloadURL(url) {
    local req := ComObject("Msxml2.XMLHTTP")
    req.open("GET", url, true)
    req.send()
    while req.readyState != 4
        Sleep 100
    if req.status == 200 {
        return req.responseText
    } else
        throw Error("Download failed", -1, url)
}

; Forum Topic: www.autohotkey.com/forum/topic51342.html
UnHTM( HTM ) { ; Remove HTML formatting / Convert to ordinary text     by SKAN 19-Nov-2009
    Static HT := "&aacuteá&acircâ&acute´&aeligæ&agraveà&amp&aringå&atildeã&au" 
        . "mlä&bdquo„&brvbar¦&bull•&ccedilç&cedil¸&cent¢&circˆ&copy©&curren¤&dagger†&dagger‡&deg" 
        . "°&divide÷&eacuteé&ecircê&egraveè&ethð&eumlë&euro€&fnofƒ&frac12½&frac14¼&frac34¾&gt>&h" 
        . "ellip…&iacuteí&icircî&iexcl¡&igraveì&iquest¿&iumlï&laquo«&ldquo“&lsaquo‹&lsquo‘&lt<&m" 
        . "acr¯&mdash—&microµ&middot·&nbsp &ndash–&not¬&ntildeñ&oacuteó&ocircô&oeligœ&ograveò&or" 
        . "dfª&ordmº&oslashø&otildeõ&oumlö&para¶&permil‰&plusmn±&pound£&quot`"&raquo»&rdquo”&reg" 
        . "®&rsaquo›&rsquo’&sbquo‚&scaronš&sect§&shy­&sup1¹&sup2²&sup3³&szligß&thornþ&tilde˜&tim" 
        . "es×&trade™&uacuteú&ucircû&ugraveù&uml¨&uumlü&yacuteý&yen¥&yumlÿ"
    TXT := RegExReplace(HTM, "<[^>]+>"), R := ""               ; Remove all tags between  "<" and ">"
    Loop Parse, TXT, "&`;"                              ; Create a list of special characters
      L := "&" A_LoopField ";", R .= (InStr(HT, "&" A_LoopField) && !InStr(R, L, 1) ? L:"")
    R := SubStr(R, 1, -1)
    Loop Parse, R, "`;"                                ; Parse Special Characters
     If F := InStr(HT, A_LoopField)                  ; Lookup HT Data
       ; StrReplace() is not case sensitive
       ; check for StringCaseSense in v1 source script
       ; and change the CaseSense param in StrReplace() if necessary
       TXT := StrReplace(TXT, A_LoopField "`;", SubStr(HT, (F+StrLen(A_LoopField))<1 ? (F+StrLen(A_LoopField))-1 : (F+StrLen(A_LoopField)), 1))
     Else If ( SubStr(A_LoopField, 2, 1)="#" )
       ; StrReplace() is not case sensitive
       ; check for StringCaseSense in v1 source script
       ; and change the CaseSense param in StrReplace() if necessary
       TXT := StrReplace(TXT, A_LoopField "`;", SubStr(A_LoopField, 3))
   Return RegExReplace(TXT, "(^\s*|\s*$)")            ; Remove leading/trailing white spaces
}

MoveFilesAndFolders(SourcePattern, DestinationFolder, DoOverwrite := false) {
    if DoOverwrite = 1
        DoOverwrite := 2  ; See DirMove for description of mode 2 vs. 1.
    ; First move all the files (but not the folders):
    FileMove SourcePattern, DestinationFolder, DoOverwrite
    ; Now move all the folders:
    Loop Files, SourcePattern, "D"  ; D means "retrieve folders only".
        DirMove A_LoopFilePath, DestinationFolder "\" A_LoopFileName, DoOverwrite
}

MD5(s) {
    size := StrPut(s, "UTF-8") - 1 ; bin has no null
    bin := Buffer(size)
    StrPut(s, bin, "UTF-8")
 
    MD5_CTX := Buffer(104)
    DllCall("advapi32\MD5Init", "ptr", MD5_CTX)
    DllCall("advapi32\MD5Update", "ptr", MD5_CTX, "ptr", bin, "uint", size)
    DllCall("advapi32\MD5Final", "ptr", MD5_CTX)
 
    VarSetStrCapacity(&md5, 32 + 1) ; str has null
    DllCall("crypt32\CryptBinaryToString", "ptr", MD5_CTX.ptr+88, "uint", 16, "uint", 0x4000000c, "str", md5, "uint*", 33)
    return md5
}

RegExMatchAll(haystack, needleRegEx, startingPosition := 1) {
	out := [], end := StrLen(haystack)+1
	While startingPosition < end && RegExMatch(haystack, needleRegEx, &outputVar, startingPosition)
		out.Push(outputVar), startingPosition := outputVar.Pos + (outputVar.Len || 1)
	return out
}

class Mapi extends Map {
    CaseSense := "Off"
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