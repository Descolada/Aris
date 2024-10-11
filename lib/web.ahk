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