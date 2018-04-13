transputer-eforth
=================
This repository contains eForth, ported to the Transputer by Bob Barr, with
further changes to port it to the <a href="https://devzendo.github.io/parachute/">Parachute project's</a> Transputer emulator by
Matt Gumbley.


The original version of this is contained in the eforth-transputer.zip file,
which was located via the Internet Archive's Wayback Machine at 
```
https://web.archive.org/web/20071025152055if_/http://www.eforth.com.tw/academy-n/zip/transpef.zip
```
The original location being
```
http://www.eforth.com.tw/academy-n/zip/transpef.zip
```
which is no longer available.

A more available archive may be found at
```
http://www.forth.org/library/eforth_SOC/eforth_SOC_source/eForth1/transpef.zip
```


About eForth
------------
The following description was taken from <a href="http://www.forth.org/eforth.html">Forth.org's eForth Page</a> which
houses many ports of eForth:


History of eForth - Kevin Appert:

"eForth was developed several years ago by Bill Muench. He built a simple
meta-compiled Forth that has some interesting aspects. The main goal as I
understand it was portability. Bill writes: "eForth allows me to make a complete
Forth system with about 30 very simple machine code routines. With so few words
to code, I could do the coding by hand, that is, without the need to write an
assembler first. After this simple model is running, it is desirable to code
much of the rest in assembly." The descendant of this original work is on Bill's
website.

After that, C.H. Ting wanted a simple, portable Forth to be the new
FIG-Forth. He wanted to have a Forth to spread around, to use for his own work
and to be a part of his "Firmware Engineering Workshop". At Ting's request Bill
coded eForth in MASM to produce an assembly listing much like the original
FIG-Forth distribution. Ting felt that more common folk could get started with a
process that didn't involve the complexities of a meta-compiler. Ting and others
have continued to evolve eForth, porting to many processors and environments.
There's even a Linux port. Ting is working on an eForth variant in C."


About Parachute eForth
----------------------
The eForth directory found in this repository contains porting done to Bob
Barr's original work, to provide an eForth that will run on the Parachute
project's Transputer emulator.

This porting is also in the public domain.

Please see the <a href="https://devzendo.github.io/parachute/">DevZendo.org Parachute Project</a> for more information.


License
-------
As the page on www.forth.org above states:

"This is a collection of Forth programs and Forth hardware designs placed in the
public domain by the eForth Group to encourage hardware and software engineers
to study and evaluate computers and software based on the eForth model."


Matt Gumbley, Fri 13 Apr 2018.

