all: cutstream.c
	gcc $(CFLAGS) -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64 -D_LARGEFILE64_SOURCE -o cutstream cutstream.c

clean:
	-rm -f cutstream
