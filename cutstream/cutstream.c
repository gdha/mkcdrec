/****************************************************************
** cutstream.c program goal is to cut the input stream into    **
** pieces of MAXCDSIZE (see config.h) and execute a program    **
** via system(prg) call.                                       **
**                                                             **
** Author: Gratien D'haese  IT3 Consultants                    **
** Copyright (C) by Gratien D'haese - GPL license	       **
*****************************************************************/

/* History
   =======
v0.6: fix compile problems with older gcc versions by Jérôme Warnier
v0.5: config.h replaced by /tmp/cutsream.h (dyn. created by rd-base.sh) and
      that file will be read and written into the maxcdsize variable
      Gratien D'haese - 25 Aug. 2003
v0.4: make cutstream 64 bit aware for DVD support (Gratien D'haese)
v0.3: io buffered in filepipe by Jason Bertschi <phantom@spinnakernet.com>
v0.2: in function filepipe: do not reread the CAPACITY environment,
      but instead set to maxcdsize (02/02/2001)
v0.1: original version
*/

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
/*#include "config.h"*/

#define CUTSTREAM_VERSION "0.6"
#define PROGNAME "cutstream"
#define NAMELENGTH 254

extern char **environ;
long long int i = 0, total = 0;
long long int maxcdsize = 0; /* size in Kbytes */
char *dstname;

main (int argc, char *argv[])
{

 FILE *fp, *dst, *fp_conf;
 void filepipe (FILE *, FILE *);
 char *prog = argv [0];

 /* The MAXCDSIZE variable is kept in /tmp/cutstream.h (created by rd-base.sh
    script each time mkcdrec runs). Cutstream will read this variable and
    store it in maxcdsize variable (long long int so it can contain a number
    long enough for DVD purposes.
    Before maxcdsize was compiled into the executable which was bad for e.g.
    DVD users.
    FIX by Gratien D'haese - 25 Aug. 2003
 */
 char *cutstream_h = "/tmp/cutstream.h"; /* file contains nr in Kb */
 char maxcdsize_l[NAMELENGTH];
 if ((fp_conf = fopen(cutstream_h, "r")) == NULL ) {
	fprintf(stdout, "%s: error reading %s\n", prog, cutstream_h);
	exit(1);
	}
 fgets (maxcdsize_l,NAMELENGTH,fp_conf);
 maxcdsize = atoll(maxcdsize_l);
 fprintf(stdout, "%s: maxcdsize = %d\n", prog, maxcdsize);
 fclose(fp_conf);

  dstname = getenv ("DESTINATION");
  if (dstname == NULL)
     dstname = "Output";

 if ((dst = fopen(dstname, "w")) == (FILE *)NULL) {
     fprintf(stdout, "%s: error writing destination %s\n", prog, dstname);
     exit(1);
     }

 if (argc == 1) /* no args; copy to dstname file */
	filepipe(stdin, dst);
 else
     while (--argc > 0)
	if ((fp = fopen(*++argv, "r")) == NULL) {
	  fprintf(stdout, "%s: can't open input file %s\n", prog, *argv);
	  return 1;
	} else {
	  filepipe(fp, dst);
	  fclose(fp);
	}
 if (ferror(dst)) {
	fprintf(stdout, "%s: error writing destination %s\n", prog, dstname);
	exit(2);
	}
 fclose(dst);
 exit(0); 
}

#define MAXIOSIZE 4096

/* filepipe: copy file ifp to file ofp */
void filepipe(FILE *ifp, FILE *ofp)
{
  int c, volno;
  long long int capacity, i=0; /* 10 digits max */
  char *cap, *volno_file, volno_l[NAMELENGTH];
  FILE *fdvolno;
  long int numRead; /* size_t is int32 fread/fwrite function */
  long int writeProgress;
  unsigned char data[MAXIOSIZE];
  long int trialReadSize, total;


  char *prg = getenv ("MAKE_ISO9660");
  if (prg == NULL)
     prg = "makeISO9660.sh";

  dstname = getenv ("DESTINATION");
  if (dstname == NULL)
     dstname = "Output";

  /* Part volume number: read environment variable VOLNO_FILE which is 0
     for single CD image, or 1 or higher for each following CD image
  */
  volno_file = getenv ("VOLNO_FILE"); /* Volume number 0: single, >1 multi */
  if (volno_file == NULL)
	volno = -1;
  if ((fdvolno = fopen(volno_file, "r")) == NULL) {
	fprintf(stdout, "%s: error opening volno file %s\n", PROGNAME, volno_file);
	exit(1);
	}
  fgets (volno_l,NAMELENGTH,fdvolno); 
  volno = atoi(volno_l);
  fclose(fdvolno);

  fprintf(stdout, "%s: volno nummer is %d\n", PROGNAME, volno);

  /* Part capacity left on CD image free for backups of user data. Read
     environment variable CAPACITY - set by tar-it.sh. When not set or
     for multiple image reset CAPACITY to maxcdsize (see main part of
     cutstream)
  */
  cap = getenv ("CAPACITY"); /* capacity of CD in Kb */
  if (cap == NULL)
	capacity = maxcdsize;
  else
	capacity = atoll(cap); /* fix: atol became atoll (long long) */

  fprintf(stdout,"%s: CAPACITY left is %Ld Kbytes.\n", PROGNAME, capacity);
  capacity = capacity * 1024; /* Kb to bytes */

  /* Part read pipe from tar command and cut pieces of size capacity till
     eof
  */
  while (!feof(ifp))
    {
	trialReadSize = MAXIOSIZE;
	if (trialReadSize > capacity - i) 
	    trialReadSize = capacity - i;

	numRead = fread(data, 1, trialReadSize, ifp);
	writeProgress = 0;
	while (writeProgress < numRead)
	    writeProgress += fwrite(&data[writeProgress], 1,
				    numRead - writeProgress, ofp);
	i+= numRead;

	if (numRead < MAXIOSIZE) {
	    printf("only %d bytes read at relative offset %d\n", numRead, i);
	    }

	if ( i == capacity ) {	/* need to cut the input stream */
	   fprintf (stdout,"Starting %s - can take a while.\n", prg);
	   volno++; /* increment volume nr. */
	   if ((fdvolno = fopen(volno_file, "w")) == NULL) {
             fprintf(stdout, "%s: error opening volno file %s\n", PROGNAME, volno_file);
             exit(1);
             }
	   fprintf(fdvolno,"%d\n", volno);
	   fclose(fdvolno);	/* close volno file */
	   fclose(ofp);		/* close destination file */
	   system(prg);		/* call program MAKE_ISO9660 */
	   /*  fopen: "w" Truncate  file to zero length or create text file
               for writing. The stream is positioned at the beginning of the
               file. File was removed by makeISO9660.sh */
	   if ((ofp = fopen(dstname, "w")) == (FILE *)NULL) {
		fprintf(stdout, "%s: error writing destination %s\n", PROGNAME, dstname);
		exit(10);
		}
	   /* reset the CAPACITY counter to maxcdsize */
	   capacity = maxcdsize * 1024; /* Kb to bytes */

	   fprintf(stdout,"%s: CAPACITY left is %d bytes.\n", PROGNAME, capacity);

	   total = total + i;	/* to get total bytes of file at the end */
	   i = 0;		/* reset counter i to 0 */
	}			/* end of need to cut the input stream */
    }
    total = total + i;		/* total bytes of file at the end */
    fprintf (stdout,"%s: %s bytes transferred: %d\n",PROGNAME, dstname, total);
}
