# Makefile for ITA TOOLBOX #7 mv

AS	= HAS.X -i $(INCLUDE)
LK	= hlk.x -x
CV      = -CV.X -r
CP      = cp
RM      = -rm -f

INCLUDE = $(HOME)/fish/include

DESTDIR   = A:/usr/ita
BACKUPDIR = B:/mv/1.2
RELEASE_ARCHIVE = MV12
RELEASE_FILES = MANIFEST README ../NOTICE ../DIRECTORY CHANGES mv.1 mv.x

EXTLIB = ../lib/getlnenv.o $(HOME)/fish/lib/ita.l

###

PROGRAM = mv.x

###

.PHONY: all clean clobber install release backup

.TERMINAL: *.h *.s

%.r : %.x	; $(CV) $<
%.x : %.o	; $(LK) $< $(EXTLIB)
%.o : %.s	; $(AS) $<

###

all:: $(PROGRAM)

clean::

clobber:: clean
	$(RM) *.bak *.$$* *.o *.x

###

$(PROGRAM) : $(INCLUDE)/doscall.h $(INCLUDE)/chrcode.h $(EXTLIB)

include ../Makefile.sub

###
