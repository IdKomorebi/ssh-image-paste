#Requires AutoHotkey v2.0
#SingleInstance Force

CONFIG := A_ScriptDir "\config.ini"
if !FileExist(CONFIG) {
    MsgBox("Run windows\install.ps1 -HostName YOUR_SSH_ALIAS first.", "SSH Image Paste")
    ExitApp()
}
HOST := IniRead(CONFIG, "ssh-image-paste", "HostName", "")
MODE := IniRead(CONFIG, "ssh-image-paste", "Mode", "clipboard")
DISPLAY_NO := IniRead(CONFIG, "ssh-image-paste", "Display", ":99")
REMOTE_HELPER := IniRead(CONFIG, "ssh-image-paste", "RemoteHelper", "~/.local/bin/ssh-image-paste-server")
APP_EXE := IniRead(CONFIG, "ssh-image-paste", "AppExe", "Code.exe")
if !RegExMatch(HOST, "^[A-Za-z0-9][A-Za-z0-9_.@-]*$")
    || !RegExMatch(DISPLAY_NO, "^:[0-9]+$")
    || !(MODE = "clipboard" || MODE = "path")
    || RegExMatch(REMOTE_HELPER, '[\r\n"]')
    || !RegExMatch(APP_EXE, "^[A-Za-z0-9 ._-]+\.exe$") {
    MsgBox("Invalid config.ini. See config.example.ini.", "SSH Image Paste")
    ExitApp()
}
PS1 := A_ScriptDir "\paste-image.ps1"
OUT := A_Temp "\ssh-image-paste-" ProcessExist() ".out"
busy := false
A_IconTip := "SSH Image Paste | " HOST " | Alt+V"

ClipHasImage() {
    return DllCall("IsClipboardFormatAvailable", "UInt", 8)
        || DllCall("IsClipboardFormatAvailable", "UInt", 17)
        || DllCall("IsClipboardFormatAvailable", "UInt", 2)
}
Notify(message) {
    ToolTip(message)
    SetTimer(() => ToolTip(), -3500)
}
TargetActive() {
    return WinActive("ahk_exe " APP_EXE)
}

#HotIf TargetActive()
$!v:: {
    global busy
    if busy
        return
    if !ClipHasImage() {
        Send("{Alt down}v{Alt up}")
        return
    }
    busy := true
    targetWindow := WinExist("A")
    try {
        try FileDelete(OUT)
        command := Format('powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "{1}" -HostName "{2}" -Mode "{3}" -Display "{4}" -RemoteHelper "{5}" -OutFile "{6}"',
            PS1, HOST, MODE, DISPLAY_NO, REMOTE_HELPER, OUT)
        result := RunWait(command, , "Hide")
        if result != 0 {
            Notify("Upload failed (" result "). See %LOCALAPPDATA%\ssh-image-paste\paste-image.log")
            return
        }
        KeyWait("Alt", "T2")
        if !WinActive("ahk_id " targetWindow) {
            Notify("Uploaded. Return to the original CLI input and press Alt+V again.")
            return
        }
        if MODE = "path" {
            A_Clipboard := Trim(FileRead(OUT, "UTF-8")) " "
            Sleep(50)
            Send("^v")
        } else {
            Send("{Alt down}v{Alt up}")
        }
    } catch as err {
        Notify("Image paste failed: " err.Message)
    } finally {
        busy := false
        try FileDelete(OUT)
    }
}
#HotIf
