;{ [Class] GuiReSizer
; Fanatic Guru
; Version 2023 03 13
;
; Update 2023 02 15:  Add more Min Max properties and renamed some Properties
; Update 2023 03 13:  Major rewrite.  Converted to Class to allow for Methods
;
; #Requires AutoHotkey v2.0.2+
;
; Class to Handle the Resizing of Gui and
; Move and Resize Controls
;
;------------------------------------------------
;
;   Class GuiReSizer
;
;   Call: GuiReSizer(GuiObj, WindowMinMax, Width, Height)
;
;   Parameters:
;	1) {GuiObj} 		Gui Object
;   2) {WindowMinMax}	Window status, 0 = neither minimized nor maximized, 1 = maximized, -1 = minimized
;   3) {Width}			Width of GuiObj
;   4) {Height}			Height of GuiObj
;
;   	Normally parameters are passed by a callback from {gui}.OnEvent("Size", GuiReSizer)
;
;	Properties:		Abbr	Description
; 		X					X positional offset from margins
;		Y					Y positional offset from margins
; 		XP					X positional offset from margins as percentage of Gui width
; 		YP					Y positional offset from margins as percentage of Gui height
;		OriginX		OX		control origin X defaults to 0 or left side of control, this relocates the origin
;		OriginXP	OXP		control origin X as percentage of Gui width defaults to 0 or left side of control, this relocates the origin
;		OriginY		OY		control origin Y defaults to 0 or top side of control, this relocates the origin
;		OriginYP	OYP		control origin Y as percentage of Gui height defaults to 0 or top side of control, this relocates the origin
;		Width		W		width of control
;		WidthP		WP		width of control as percentage of Gui width
;		Height		H		height of control
;		HeightP		HP		height of control as percentage of Gui height
;		MinX				mininum X offset
;		MaxX				maximum X offset
;		MinY				minimum Y offset
;		MaxY				maximum Y offset
;		MinWidth	MinW	minimum control width
;		MaxWidth	MaxW	maximum control width
;		MinHeight	MinH	minimum control height
;		MaxHeight	MaxH	maximum control height
;		Cleanup		C		{true/false} when set to true will redraw this control each time to cleanup artifacts, normally not required and causes flickering
;		Function	F		{function} custom function that will be called for this control
;		Anchor		A		{contol object} anchor control so that size and position commands are in relation to another control
;		AnchorIn	AI		{true/false} controls where the control is restricted to the inside of another control
;
;   Methods:
;       Now(GuiObj)         will force a manual Call now for {GuiObj}
;       Opt({switches})     same as Options method
;       Options({switches}) all options are set as a string with each switch separated by a space "x10 yp50 oCM"
;           Flags:
;           x{number}       X
;           y{number}       Y
;           xp{number}      XP
;           yp{number}      YP
;           wp{number}      WidthP
;           hp{number}      HeightP
;           w{number}       Width
;           h{number}       Height
;           minx{number}    MinX
;           maxx{number}    MaxX
;           miny{number}    MinY
;           maxy{number}    MaxY
;           minw{number}    MinWidth
;           maxw{number}    MaxWidth
;           minh{number}    MinHeight
;           maxh{number}    MaxHeight
;           oxp{number}     OriginXP
;           oyp{number}     OriginYP
;           ox{number}      OriginX
;           oy{number}      OriginY
;           o{letters}      Origin: "L" left, "C" center, "R" right, "T" top, "M" middle, "B" bottom; may use 1 or 2 letters
;
;	Gui Properties:
;		Init		{Gui}.Init := 1, will cause all controls of the Gui to be redrawn on next function call
;                   {Gui}.Init := 2, will also reinitialize abbreviations
;
Class GuiReSizer
{
    ;{ Call GuiReSizer
    Static Call(GuiObj, WindowMinMax, GuiW, GuiH)
    {
        ; On Initial display of Gui use redraw to cleanup first positioning
        Try
            (GuiObj.Init)
        Catch
            GuiObj.Init := 2 ; Redraw Twice on Initial Call(called on initial Show)

        If WindowMinMax = -1 ; Do nothing if window minimized
            Return

        ;{ Loop through all Controls of Gui
        For Hwnd, CtrlObj in GuiObj
        {
            ;{ Initializations on First Call
            If GuiObj.Init = 2
            {
                Try CtrlObj.OriginX := CtrlObj.OX
                Try CtrlObj.OriginXP := CtrlObj.OXP
                Try CtrlObj.OriginY := CtrlObj.OY
                Try CtrlObj.OriginYP := CtrlObj.OYP
                Try CtrlObj.Width := CtrlObj.W
                Try CtrlObj.WidthP := CtrlObj.WP
                Try CtrlObj.Height := CtrlObj.H
                Try CtrlObj.HeightP := CtrlObj.HP
                Try CtrlObj.MinWidth := CtrlObj.MinW
                Try CtrlObj.MaxWidth := CtrlObj.MaxW
                Try CtrlObj.MinHeight := CtrlObj.MinH
                Try CtrlObj.MaxHeight := CtrlObj.MaxH
                Try CtrlObj.Function := CtrlObj.F
                Try CtrlObj.Cleanup := CtrlObj.C
                Try CtrlObj.Anchor := CtrlObj.A
                Try CtrlObj.AnchorIn := CtrlObj.AI
                If !CtrlObj.HasProp("AnchorIn")
                    CtrlObj.AnchorIn := true
            }
            ;}
            ;{ Initialize Current Positions and Sizes
            CtrlObj.GetPos(&CtrlX, &CtrlY, &CtrlW, &CtrlH)
            LimitX := AnchorW := GuiW, LimitY := AnchorH := GuiH, OffsetX := OffsetY := 0
            ;}
            ;{ Check for Anchor
            If CtrlObj.HasProp("Anchor")
            {
                If Type(CtrlObj.Anchor) = "Gui.Tab"
                {
                    CtrlObj.Anchor.GetPos(&AnchorX, &AnchorY, &AnchorW, &AnchorH)
                    Offset(CtrlObj, &TabX, &TabY)
                    CtrlX := CtrlX - TabX, CtrlY := CtrlY - TabY
                    AnchorW := AnchorW + AnchorX - TabX, AnchorH := AnchorH + AnchorY - TabY
                }
                Else
                {
                    CtrlObj.Anchor.GetPos(&AnchorX, &AnchorY, &AnchorW, &AnchorH)
                    If CtrlObj.HasProp("X") or CtrlObj.HasProp("XP")
                        OffsetX := AnchorX
                    If CtrlObj.HasProp("Y") or CtrlObj.HasProp("YP")
                        OffsetY := AnchorY
                }
                If CtrlObj.AnchorIn
                    LimitX := AnchorW, LimitY := AnchorH
            }
            ;}
            ;{ OriginX
            If CtrlObj.HasProp("OriginX") and CtrlObj.HasProp("OriginXP")
                OriginX := CtrlObj.OriginX + (CtrlW * CtrlObj.OriginXP)
            Else If CtrlObj.HasProp("OriginX") and !CtrlObj.HasProp("OriginXP")
                OriginX := CtrlObj.OriginX
            Else If !CtrlObj.HasProp("OriginX") and CtrlObj.HasProp("OriginXP")
                OriginX := CtrlW * CtrlObj.OriginXP
            Else
                OriginX := 0
            ;}
            ;{ OriginY
            If CtrlObj.HasProp("OriginY") and CtrlObj.HasProp("OriginYP")
                OriginY := CtrlObj.OriginY + (CtrlH * CtrlObj.OriginYP)
            Else If CtrlObj.HasProp("OriginY") and !CtrlObj.HasProp("OriginYP")
                OriginY := CtrlObj.OriginY
            Else If !CtrlObj.HasProp("OriginY") and CtrlObj.HasProp("OriginYP")
                OriginY := CtrlH * CtrlObj.OriginYP
            Else
                OriginY := 0
            ;}
            ;{ X
            If CtrlObj.HasProp("X") and CtrlObj.HasProp("XP")
                CtrlX := Mod(LimitX + CtrlObj.X + (AnchorW * CtrlObj.XP) - OriginX, LimitX)
            Else If CtrlObj.HasProp("X") and !CtrlObj.HasProp("XP")
                CtrlX := Mod(LimitX + CtrlObj.X - OriginX, LimitX)
            Else If !CtrlObj.HasProp("X") and CtrlObj.HasProp("XP")
                CtrlX := Mod(LimitX + (AnchorW * CtrlObj.XP) - OriginX, LimitX)
            ;}
            ;{ Y
            If CtrlObj.HasProp("Y") and CtrlObj.HasProp("YP")
                CtrlY := Mod(LimitY + CtrlObj.Y + (AnchorH * CtrlObj.YP) - OriginY, LimitY)
            Else If CtrlObj.HasProp("Y") and !CtrlObj.HasProp("YP")
                CtrlY := Mod(LimitY + CtrlObj.Y - OriginY, LimitY)
            Else If !CtrlObj.HasProp("Y") and CtrlObj.HasProp("YP")
                CtrlY := Mod(LimitY + AnchorH * CtrlObj.YP - OriginY, LimitY)
            ;}
            ;{ Width
            If CtrlObj.HasProp("Width") and CtrlObj.HasProp("WidthP")
                (CtrlObj.Width > 0 and CtrlObj.WidthP > 0 ? CtrlW := CtrlObj.Width + AnchorW * CtrlObj.WidthP : CtrlW := CtrlObj.Width + AnchorW + AnchorW * CtrlObj.WidthP - CtrlX)
            Else If CtrlObj.HasProp("Width") and !CtrlObj.HasProp("WidthP")
                (CtrlObj.Width > 0 ? CtrlW := CtrlObj.Width : CtrlW := AnchorW + CtrlObj.Width - CtrlX)
            Else If !CtrlObj.HasProp("Width") and CtrlObj.HasProp("WidthP")
                (CtrlObj.WidthP > 0 ? CtrlW := AnchorW * CtrlObj.WidthP : CtrlW := AnchorW + AnchorW * CtrlObj.WidthP - CtrlX)
            ;}
            ;{ Height
            If CtrlObj.HasProp("Height") and CtrlObj.HasProp("HeightP")
                (CtrlObj.Height > 0 and CtrlObj.HeightP > 0 ? CtrlH := CtrlObj.Height + AnchorH * CtrlObj.HeightP : CtrlH := CtrlObj.Height + AnchorH + AnchorH * CtrlObj.HeightP - CtrlY)
            Else If CtrlObj.HasProp("Height") and !CtrlObj.HasProp("HeightP")
                (CtrlObj.Height > 0 ? CtrlH := CtrlObj.Height : CtrlH := AnchorH + CtrlObj.Height - CtrlY)
            Else If !CtrlObj.HasProp("Height") and CtrlObj.HasProp("HeightP")
                (CtrlObj.HeightP > 0 ? CtrlH := AnchorH * CtrlObj.HeightP : CtrlH := AnchorH + AnchorH * CtrlObj.HeightP - CtrlY)
            ;}
            ;{ Min Max
            (CtrlObj.HasProp("MinX") ? MinX := CtrlObj.MinX : MinX := -999999)
            (CtrlObj.HasProp("MaxX") ? MaxX := CtrlObj.MaxX : MaxX := 999999)
            (CtrlObj.HasProp("MinY") ? MinY := CtrlObj.MinY : MinY := -999999)
            (CtrlObj.HasProp("MaxY") ? MaxY := CtrlObj.MaxY : MaxY := 999999)
            (CtrlObj.HasProp("MinWidth") ? MinW := CtrlObj.MinWidth : MinW := 0)
            (CtrlObj.HasProp("MaxWidth") ? MaxW := CtrlObj.MaxWidth : MaxW := 999999)
            (CtrlObj.HasProp("MinHeight") ? MinH := CtrlObj.MinHeight : MinH := 0)
            (CtrlObj.HasProp("MaxHeight") ? MaxH := CtrlObj.MaxHeight : MaxH := 999999)
            CtrlX := MinMax(CtrlX, MinX, MaxX)
            CtrlY := MinMax(CtrlY, MinY, MaxY)
            CtrlW := MinMax(CtrlW, MinW, MaxW)
            CtrlH := MinMax(CtrlH, MinH, MaxH)
            ;}
            ;{ Move and Size
            CtrlObj.Move(CtrlX + OffsetX, CtrlY + OffsetY, CtrlW, CtrlH)
            ;}
            ;{ Redraw on Cleanup or GuiObj.Init
            If GuiObj.Init or (CtrlObj.HasProp("Cleanup") and CtrlObj.Cleanup = true)
                CtrlObj.Redraw()
            ;}
            ;{ Custom Function Call
            If CtrlObj.HasProp("Function")
                CtrlObj.Function(GuiObj) ; CtrlObj is hidden 'this' first parameter
            ;}
        }
        ;}
        ;{ Reduce GuiObj.Init Counter and Check for Call again
        If (GuiObj.Init := Max(GuiObj.Init - 1, 0))
        {
            GuiObj.GetClientPos(, , &AnchorW, &AnchorH)
            GuiReSizer(GuiObj, WindowMinMax, AnchorW, AnchorH)
        }
        ;}
        ;{ Functions: Helpers
        MinMax(Num, MinNum, MaxNum) => Min(Max(Num, MinNum), MaxNum)
        Offset(CtrlObj, &OffsetX, &OffsetY)
        {
            Hwnd := CtrlObj.Hwnd
            hParentWnd := DllCall("GetParent", "Ptr", Hwnd, "Ptr")
            RECT := Buffer(16, 0)
            DllCall("GetWindowRect", "Ptr", hParentWnd, "Ptr", RECT)
            DllCall("MapWindowPoints", "Ptr", 0, "Ptr", DllCall("GetParent", "Ptr", hParentWnd, "Ptr"), "Ptr", RECT, "UInt", 1)
            OffsetX := NumGet(RECT, 0, "Int"), OffsetY := NumGet(RECT, 4, "Int")
        }
        ;}
    }
    ;}
    ;{ Methods:
    ;{ Options
    Static Opt(CtrlObj, Options) => GuiReSizer.Options(CtrlObj, Options)
    Static Options(CtrlObj, Options)
    {
        For Option in StrSplit(Options, " ")
        {
            For Abbr, Cmd in Map(
                "xp", "XP", "yp", "YP", "x", "X", "y", "Y",
                "wp", "WidthP", "hp", "HeightP", "w", "Width", "h", "Height",
                "minx", "MinX", "maxx", "MaxX", "miny", "MinY", "maxy", "MaxY",
                "minw", "MinWidth", "maxw", "MaxWidth", "minh", "MinHeight", "maxh", "MaxHeight",
                "oxp", "OriginXP", "oyp", "OriginYP", "ox", "OriginX", "oy", "OriginY")
                If RegExMatch(Option, "i)^" Abbr "([\d.-]*$)", &Match)
                {
                    CtrlObj.%Cmd% := Match.1
                    Break
                }
            ; Origin letters
            If SubStr(Option, 1, 1) = "o"
            {
                Flags := SubStr(Option, 2)
                If Flags ~= "i)l"           ; left
                    CtrlObj.OriginXP := 0
                If Flags ~= "i)c"           ; center (left to right)
                    CtrlObj.OriginXP := 0.5
                If Flags ~= "i)r"           ; right
                    CtrlObj.OriginXP := 1
                If Flags ~= "i)t"           ; top
                    CtrlObj.OriginYP := 0
                If Flags ~= "i)m"           ; middle (top to bottom)
                    CtrlObj.OriginYP := 0.5
                If Flags ~= "i)b"           ; bottom
                    CtrlObj.OriginYP := 1
            }
        }
    }
    ;}
    ;{ Now
    Static Now(GuiObj, Redraw := true, Init := 2)
    {
        If Redraw
            GuiObj.Init := Init
        GuiObj.GetClientPos(, , &Width, &Height)
        GuiReSizer(GuiObj, WindowMinMax := 1, Width, Height)
    }
    ;}
    ;}
}
;}