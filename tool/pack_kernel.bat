@echo off
REM 用法：tool\pack_kernel.bat <内核目录> [输出.zbk]
REM       tool\pack_kernel.bat --demo [输出.zbk]
python "%~dp0pack_kernel.py" %*
