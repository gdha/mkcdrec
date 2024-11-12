/*****************************************************************
** pastestream.c program goal is to paste several input streams **
** into one output stream.                                      **
** Author: Gratien D'haese  IT3 Consultants                     **
*****************************************************************/

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include "config.h"

#define PASTESTREAM_VERSION "0.3"
#define PROGNAME "pastestream"
#define NAMELENGTH 254

extern char **environ;
char *rstname;
char *cont;
size_t rstl;

main (int argc, char *argv[])
{

 FILE *fp, *fdi, *fdrst;
 void filepipe (FILE *, FILE *);
 char *prog = argv [0];
 int i = 1;	/* used for while loop */
 char *more_to_come, *rstname; 
 char i_str[NAMELENGTH], restore_str[NAMELENGTH];
 /* char *restore; */


 /* make a loop until .... */
 do {

  rstname = "/tmp/restore";		/* contains the fp name */
  more_to_come = "/tmp/more_to_come";	/* 1 or 0 */
 
  /* 1 ask_for_cd - min. going once through loop */
  if ((fdi = fopen(more_to_come, "r")) == NULL) {
     fprintf(stderr, "%s: cannot open %s file\n", prog, more_to_come);
     exit(1);
     }
  fgets (i_str,NAMELENGTH,fdi);
  i = atoi(i_str);
  fclose(fdi); 

  if ((fdrst = fopen(rstname, "r")) == (FILE *)NULL) {
    fprintf(stderr, "%s: cannot open the file %s\n", prog, rstname);
    exit(1);
    }
  fgets (restore_str,NAMELENGTH,fdrst);
  fclose(fdrst);

 /* strncpy (restore, restore_str, strlen(restore_str));
  restore[strlen(restore_str)-1]='\0';
*/
  restore_str[strlen(restore_str)-1]='\0';

  if ((fp = fopen(restore_str, "r"))  == (FILE *)NULL) {
    fprintf(stderr, "%s: cannot open %s!\n", prog, restore_str);
    exit(1);
    }

  filepipe(fp, stdout);
  fclose(fp);
  
  if (ferror(stdout)) {
	fprintf(stderr, "%s: error writing stdout\n", prog);
	exit(2);
 	}
  if ( i )
    system(ASK_FOR_CD);	/* call shell script defined in config.h */

 } while ( i );	/* end of while */
 
exit(0);

}	/* end of main */


#define MAXIOSIZE 4096

/* filepipe: copy file ifp to file ofp */
void filepipe(FILE *ifp, FILE *ofp)
{
  int numRead;
  unsigned char data[MAXIOSIZE];
  int writeProgress;

/* Modified by Jason Bertschi <phantom@spinnakernet.com> */
  while(!feof(ifp)) {
	numRead = fread(data, 1, MAXIOSIZE, ifp);
	writeProgress = 0;
	while (writeProgress < numRead)
		writeProgress += fwrite(&data[writeProgress], 1,
					numRead - writeProgress, ofp);
  }
}
