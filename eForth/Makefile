# Makefile using DevZendo.org Transputer Macro Assembler

EFORTH.BIN: EFORTH.ASM
	tmasm -l EFORTH.LST -b EFORTH.BIN EFORTH.ASM

clean:
	rm -f EFORTH.BIN EFORTH.OUT EFORTH.LST
