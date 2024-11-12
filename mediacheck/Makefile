# Software for checking and implanting md5sum on a ISO 9660 image
# Taken from the "anaconda-7.3" source package from RedHat 7.3

VERSION = 1.0


OBJS = md5.o mediacheck.o checkisomd5.o implantisomd5.o

SOURCES = $(subst .o,.c,$(OBJS)) 
DEBUG =

BINS=checkisomd5 implantisomd5

COPTS = $(DEBUG) -Wall -DVERSION='"$(VERSION)"' -DTESTING

CC=gcc
STATIC=#-static
LIBS=-lnewt -lslang

all: $(BINS)

mediacheck: md5.o mediacheck.o
	$(CC) -o $@ $(STATIC) md5.o mediacheck.o $(LIBS)

md5.o: md5.c md5.h
	$(CC) -O $(COPTS) -c -o md5.o md5.c

mediacheck.o: mediacheck.c mediacheck.h
	$(CC) -O $(COPTS) -c -o mediacheck.o mediacheck.c

checkisomd5: checkisomd5.c md5.o
	$(CC) -O -o checkisomd5 -DTESTING checkisomd5.c md5.o -lm

implantisomd5: implantisomd5.c md5.o
	$(CC) -O -o implantisomd5 implantisomd5.c md5.o -lm

install: all
	mkdir -p $(DESTDIR)/usr/bin
	install -m755 -s checkisomd5 $(DESTDIR)/usr/bin
	install -m755 -s implantisomd5 $(DESTDIR)/usr/bin

clean: 
	rm -f *.o *~ mediacheck checkisomd5 implantisomd5

