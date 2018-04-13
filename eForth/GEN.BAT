@echo off
rem tasm /l eforth,eforth,eforth
tasm eforth
tlink eforth /3
fixfile eforth.exe eforth.com
