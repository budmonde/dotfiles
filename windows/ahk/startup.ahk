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
