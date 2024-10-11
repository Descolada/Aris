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
        return (v) => CompareFunc(v) && GetVersionRangeCompareFunc(OtherRange).Call(v)
    return CompareFunc
}

IsVersionSha(version) => StrLen(version) = 7 && IsAlnum(version)
IsVersionMD5(version) => StrLen(version) = 10 && IsAlnum(version)
IsSemVer(input) => !RegExMatch(input, "(^\w{7}$)|^\w{10}$") && RegExMatch(input, "^[><=^~]*v?(?:((0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?)|\d+|\d+\.\d+|latest|\*)$")
IsVersionCompatible(version, range) => GetVersionRangeCompareFunc(range).Call(version)