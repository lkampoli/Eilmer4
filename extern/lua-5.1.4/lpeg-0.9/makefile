LUADIR = ../include

COPT = -O2 -DNDEBUG

CWARNS = -Wall -Wextra -pedantic \
        -Waggregate-return \
	-Wbad-function-cast \
        -Wcast-align \
        -Wcast-qual \
	-Wdeclaration-after-statement \
	-Wdisabled-optimization \
        -Wmissing-prototypes \
        -Wnested-externs \
        -Wpointer-arith \
        -Wshadow \
	-Wsign-compare \
	-Wstrict-prototypes \
	-Wundef \
        -Wwrite-strings \
	-Wno-unused-function 


CFLAGS = $(CWARNS) $(COPT) -ansi -I$(LUADIR)
DLLFLAGS = -shared
CC = gcc

lpeg.so: lpeg.o
	$(CC) $(DLLFLAGS) lpeg.o -o lpeg.so

lpeg.o:	makefile lpeg.c

test: test.lua re.lua lpeg.so
	test.lua

clean:
	- rm lpeg.so lpeg.o
