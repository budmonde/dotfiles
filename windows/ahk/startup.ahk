#SingleInstance Force

; Re-program CapsLock key behavior

CapsLock:: {
    Send("{Escape}")
}

+CapsLock:: {
    SetCapsLockState(GetKeyState("CapsLock", "T") ? "Off" : "On")
}

; Ctrl+Alt+Pause — Sleep
^!Pause:: {
    DllCall("powrprof\SetSuspendState", "Int", 0, "Int", 1, "Int", 0)
}

; Ctrl+Alt+T — WSL terminal (bring to front if running, else launch)
^!t:: {
    if WinExist("Ubuntu ahk_exe WindowsTerminal.exe") {
        WinActivate()
    } else {
        Run("wt.exe -p Ubuntu")
    }
}

; Win+/ — Hotkey cheat sheet overlay
#/:: {
    ShowCheatSheet()
}

ShowCheatSheet() {
    static overlay := 0

    if overlay {
        overlay.Destroy()
        overlay := 0
        return
    }

    cheatsheet := "
    (
    POWERTOYS
      Win+Alt+V          AdvancedPaste (AI paste)
      Win+Ctrl+Alt+V     Paste as plain text
      Win+Ctrl+T         AlwaysOnTop (pin window)
      Win+Ctrl+=/-       AlwaysOnTop opacity +/-
      Win+Shift+C        ColorPicker
      Win+Alt+Space      CmdPal (command palette)
      Ctrl+1             ZoomIt: zoom
      Ctrl+2             ZoomIt: draw
      Ctrl+3             ZoomIt: break timer
      Ctrl+4             ZoomIt: live zoom
      Ctrl+5             ZoomIt: record
      Ctrl+6             ZoomIt: snip
      Alt+Drag           GrabAndMove (move/resize windows)

    SYSTEM
      CapsLock           Escape
      Shift+CapsLock     Toggle CapsLock
      Ctrl+Alt+Pause     Sleep
      Ctrl+Alt+T         WSL terminal

    WINDOWS
      Win+V              Clipboard history
      Win+Shift+S        Screenshot (snip)
      Win+.              Emoji picker
    )"

    overlay := Gui("+AlwaysOnTop -Caption +ToolWindow")
    overlay.BackColor := "1a1a2e"
    overlay.MarginX := 24
    overlay.MarginY := 20
    overlay.SetFont("s12 cdddddd", "Cascadia Code NF")
    overlay.AddText(, cheatsheet)
    overlay.Show("AutoSize Center")

    ; Dismiss on any key, click, or after 10 seconds
    SetTimer(DismissOverlay, -10000)
    ih := InputHook("L0 T10")
    ih.KeyOpt("{All}", "E")
    ih.OnEnd := (*) => DismissOverlay()
    ih.Start()
    OnMessage(0x201, DismissOnClick)

    DismissOverlay(*) {
        SetTimer(DismissOverlay, 0)
        OnMessage(0x201, DismissOnClick, 0)
        if overlay {
            overlay.Destroy()
            overlay := 0
        }
    }

    DismissOnClick(wParam, lParam, msg, hwnd) {
        DismissOverlay()
        return 0
    }
}
