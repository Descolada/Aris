; Run this to load and then resave index.json to sort it and make visually uniform

#Requires AutoHotkey v2
#include ..\lib\packages.ahk
#include ..\lib\utils.ahk

A_FileEncoding := "UTF-8"
if (Content := FileRead("index.json")) && (IndexJson := JSON.Load(Content)) && IndexJson.Count {
    CaseInsensitiveIndex := Mapi()
    for key, value in IndexJson
        CaseInsensitiveIndex[key] := value
    if (Result := JSON.Dump(CaseInsensitiveIndex, true))
        FileOpen("index.json", "w").Write(Result)
} 
