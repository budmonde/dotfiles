; Re-program CapsLock key behavior

CapsLock:: {
    Send("{Escape}")
}

+CapsLock:: {
    SetCapsLockState(GetKeyState("CapsLock", "T") ? "Off" : "On")
}
