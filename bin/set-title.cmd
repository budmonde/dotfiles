@echo off
:: Writes an OSC 2 window-title escape. Bytes 0x1B (ESC) and 0x07 (BEL)
:: below are literal; .gitattributes marks this file -text so git preserves them.
:: Assign %~1 to a variable first so pipes/ampersands in the title do not
:: get parsed as cmd operators when the escape sequence is emitted.
setlocal enabledelayedexpansion
set "t=%~1"
<nul set /p =]2;!t!
