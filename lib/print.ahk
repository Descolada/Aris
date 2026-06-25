AttachConsole() {
    if !DllCall("AttachConsole", "UInt", 0x0ffffffff, "ptr")
        return false
        
    static STD_INPUT_HANDLE   := -10
    static STD_OUTPUT_HANDLE  := -11
    static STD_ERROR_HANDLE   := -12

    OnExit((*) => DllCall("FreeConsole"))
    hConsole := DllCall("GetStdHandle", "int", STD_OUTPUT_HANDLE)  
    
    ; Enable ANSI codes processing
    if DllCall("GetConsoleMode", "Ptr", hConsole, "UIntP", &mode := 0) {
        mode |= 0x0004  ; ENABLE_VIRTUAL_TERMINAL_PROCESSING
        DllCall("SetConsoleMode", "Ptr", hConsole, "UInt", mode)
    }
    
    return hConsole
}

; https://gist.github.com/JBlond/2fea43a3049b38287e5e9cefc87b2124
Colorize(msg, regex := "", color := "white", bold := false) {
    static colors := Map(
        "black",    30,
        "red",      31,
        "yellow",   33,
        "gray",     90,
        "green",    92,
        "blue",     94,
        "purple",   95,
        "cyan",     96,
    )
    
    if (!color || color = "white")
        return msg
    
    code  := colors.Get(color, 37)  
    
    static esc := Chr(27)
    static end := esc "[0m"
    begin      := esc "[" bold ";" code "m"
    
    if !regex
        return begin . msg . end

    return RegExReplace(
        msg, 
        regex,
        begin "$1" end
    )
}

DeColorize(str) {
    static esc := Chr(27)

    return RegExReplace(
        str, 
        "U)" esc "\[\d+;\d+m(.+)" esc "\[0m", 
        "$1"
    )
}

({}.DefineProp)(String.prototype, 'Color', {call: Colorize})
({}.DefineProp)(String.prototype, 'Strip', {call: DeColorize})


Print(msg, color := "white", bold := false, icon := '') {
    static hConsole := AttachConsole()
    
    msg .= "`n"
    
    try 
        FileAppend(msg.Color(, color, bold), "*")
    catch
        MsgBox(msg.Strip(), "Aris", icon)
    
    if !(msg && InStr(Print.Buffer, msg))
        Print.Buffer .= msg

    return false
}

PrintError(msg)   => (Print(msg, "red", ,    "Iconx"), true)
PrintWarning(msg) => (Print(msg, "yellow", , "Icon!"), true)

PrintException(ex, *) {
    return PrintError(
        "Uncaught error on line " ex.Line ": " ex.Message "`n" 
        . (ex.Extra ? "`tSpecifically: " ex.Extra "`n" : "")
    )
}