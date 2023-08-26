# Makefile using DevZendo.org Transputer Macro Assembler

EFORTH.BIN: EFORTH.ASM
	#tmasm --debug -c -x -l EFORTH.LST -b EFORTH.BIN EFORTH.ASM > EFORTH.LOG
	tmasm -x -l EFORTH.LST -b EFORTH.BIN EFORTH.ASM
	./gen-sym.pl > EFORTH.SYM

clean:
	rm -f EFORTH.BIN EFORTH.LST EFORTH.LOG EFORTH.SYM
