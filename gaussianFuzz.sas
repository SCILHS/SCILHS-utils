title 'gaussianFuzz.sas';
* primary author: Karen Olson, BCH;
* contributing authors: Jeffrey Klann, PhD
* Implements the following obfuscation algorithm:
* 1)	Low counts below a certain threshold (i.e. 11) are identified.
* 2)	The low counts� corresponding distributions such as their percentile and cumulative distributions
* are omitted by replacing the number with �T�.
* 3)	All of the remaining counts are fuzzed using a Gaussian fuzzing technique. Specifically, for each aggregate count
* in the data set, the computer picks a randomly-generated number based off of a Gaussian distribution with a mean of �0� and
* a standard deviation of �2.5.� That randomly generated number is rounded to the nearest integer, and then added to that aggregate
* count. 
**** STEP 2 is not implemented currently. *******
*
* 8/21/2017 - Numeric fields (except those excluded) are now Gaussian-fuzzed +/- 3
* 10/12/2016 - for each dataset in a directory, set vars w low values (below a threshold) to special missing value (.X);
* -- if value = 0, ok to leave it (per JK MN);
* -- output datasets go to new directory that must exist before program is run;
* -- output datasets will have same name as original;
* -- threshold criteria is applied to all numeric variables, but not to char vars that contain numbers;
* 10/25/2015 - add option to exclude variables;
* -- also, modified program to write tempid.dat file to SAS TEMP directory, not WORK directory;

* 2/6/2018;
* -- fuzz all numeric variables except those with a date format or those on an exclude list;
* -- if the dataset contained a variable named N, apply a threshold test;
*    -- if N > 0 and < threshold, set all variables to missing (.T) ;
*       except those with a format or those on an exclude list;
*    -- if N = 0 then reset it back to 0 (unfuzz);
*       -- note: all stats (e.g. mean max cumulp25) should already be missing ;
*          and this program does not change them;

*-------------------------------------------------------------------------;
*-------------------------------------------------------------------------;
* CHANGE VALUES IN THIS SECTION BELOW;
*-------------------------------------------------------------------------;
*-------------------------------------------------------------------------;
*-- change this to any directory name with original files - must include final slash;

%let dirName= C:\drnoc\;

*-- change this to directory name for new files with low values replaced - include final slash;

%let dirname2=C:\drnoc_fixed\;

*-- change this to your threshold value;

%let threshold= 11;    * -- all values LESS THAN this (but > 0) are set to  .T  (special missing value);

*-- enter a list of valid variables names to exclude;
*   -- case does not matter,  use space as delimiter between variable names;
*-- if no variables are listed below, then all numeric variables, ;
*   except those with a date format, will be fuzzed or subjected to a threshold test;

%let excludeList=Level YoungChild ADULT CritNum seq RxYear RxMonth seg incident seq; 

*-------------------------------------------------------------------------;
* DO NOT EDIT BELOW THIS LINE;
*-------------------------------------------------------------------------;
*-- define macros

*----------------------------;
%MACRO fixNum(fname,fname2);      *-- fix numeric variables (fuzz or threshold test);
*----------------------------;
* fname - input dataset;
* fname2 - output dataset with low numeric values replaced with special missing value;
* threshold - memory variable that is set outside of this macro;

*-- delete temp datasets if they exist;

proc sql; drop table temp, temp1, temp2, temp3;
quit;

*-- user-entered list of variable names;

data temp1; 
 SET sashelp.vcolumn (where=(libname=upcase(scan("&fname",1,'.'))
    and memname=upcase(scan("&fname",2,'.')) and type="num"))
    end=eof;
  length excludeList $1000. varname $50.;
  retain excludeList;
  if _n_=1 then excludelist=catx(' ',"&excludelist2",'dummyVariable');
  if format in: ('DAT' 'DD' 'DT' 'HH' 'MDY' 'MM' 'MON' 'TIM' 'TOD'
    'TWMDY' 'WEEK' 'WORDAT' 'YEAR' 'YY') 
	then excludeList=catx(' ',excludelist,name); *-- add vars w date and/or time format to exclude list;
  if eof then do;
    numVars=countW(excludeList);  *-- count words (var names) in excludeList;
    do i=1 to numVars;
      varname=upcase(scan(excludelist,i));
	  if varname ne 'DUMMYVARIABLE' then OUTPUT;
    end;
  end;
  keep varname;
run;
proc sort data=temp1 NODUPKEY; by varname;
run;

*-- numeric variables in current dataset (&fname);
*-- note: value for type is lower case, value for format is upper case; 
*-- exclude numeric variables with a date or time format;
*   -- use GET (>= truncated string) because in: operator invalid w sql;
data temp2; 
 set sashelp.vcolumn (where=(libname=upcase(scan("&fname",1,'.'))
  and memname=upcase(scan("&fname",2,'.')) and type="num")); 
  length varname $50.;
  varname=upcase(name);
  KEEP varname;
run;
proc sort data=temp2; by varname;
run;

*-- merge the two lists of variable names;

data temp3; merge temp1 (in=in_excludeList) temp2 (in=in_numVars);
  by varname;
  if in_numVars and not in_excludeList then KEEP=1;
run;

%let keepvars=;
proc sql;
  select varname into :keepVars separated by ' ' from temp3 where keep=1;
  select count(*) into :numKeep from temp3 where keep=1;
quit;

*-- read original dataset into TEMP dataset;

data temp; length orig_N 8.; 
 SET &fname;
  if 0 le N < &threshold then orig_N=N;     *-- if dataset had N var, orig_N will have a value;
  lenK=lengthN("&keepvars");                *-- lengthN = 0 if char var is blank;
  array A{*} &keepvars DUMMYVAR;
  if lenK > 0 then do;
    do i=1 to dim(A);
      A(i)= A(i) + floor(rand("Gaussian",0,2.5));  *-- fuzz all keepVars;
	  A(i)= round(A(i),5);                         *-- round to nearest 5;
      if 0 < orig_N < &threshold then do;          *-- can be true only if dataset has an N variable;
        A(i) = .T;                                 *-- if orig_N fails threshold test, ;
      end;                                         *    then set all keepVars to special missing value;
	end;      *-- end of: do i= ...;
  end;        *-- end of: if lenK>0...;
  if orig_N=0 then N=0;                            *-- reset N to 0 if orig_N was 0;
  drop orig_N lenK i dummyVar;
run;  

*-- drop N variable if it did not exist in original dataset;

proc sql;
  select max(N) into :maxN from temp;
quit;

%PUT MAX VALUE OF N IS &MAXN;

%IF &maxN = . %THEN %DO;
  data temp; set temp (drop=N);
  run;
%END;

*-- copy dataset with changes (temp) to a permanent dataset with same name as original;

data &fname2; set temp;
run;
*----------------------------;
%MEND fixnum;
*----------------------------;

*-- program starts here;

libname X "&dirname";        *-- dir for input datasets;
libname XX "&dirname2";      *-- dir for output datasets;

*-- set up mem vars for where to write tempid.dat file that this program generates;
*   -- will use default sas WORK directory so that file erases when user exits SAS;

%let work_path=%sysfunc(pathname(work));
data _null_;
  tname=cats("&work_path",'\','tempid.dat');
  call symput('datfile',strip(tname));
run;

*-- create memory variable (excludeList2) to hold list of variables to exclude from threshold fix;

data _null_;
  string=upcase("&excludeList");       *-- read in values entered by user, change to upper case;
  length string2 $1000.;               *-- create a long empty string;
  numItems=countW(string);             *-- count how many values were entered by user;
  length var1-var100 $50.;             *-- vars for each item, define 100 (more than needed);
  array A{*} var1-var100;              *-- array A for vars defined above;
  do i=1 to numItems;                  *-- loop through vars in array until remaining are empty;
    string2= catx(' ',string2,scan(string,i));
  end;
  call symput("excludelist2",strip(string2));    *-- when string complete, put it in a memory variable;
  call symput("excludeHowMany",strip(numitems)); *-- put # vars to exclude in a memory variable;
run;
%put Exclude &excludehowmany variables:  &excludelist2;

*-- delete these datasets;

proc sql;  drop table fname, fname2;
quit;

*-- get list of datasets in a directory;

ods output Directory=directory members=fnames;
proc datasets lib=x;
run;

*-- get # observations in each dataset;

proc sql;
  create table fname2 as select v.libname, v.memname, v.nobs
  from fnames f, sashelp.vtable v
  where f.name = v.memname and libname='X';
quit;

*-- write commands to copy datasets with 0 obs to new directory;

data _null_; set fname2 (where=(nobs=0));
  file "&datfile";
  length line $1000.;
  line=cats('data xx.',memname,'; set x.',memname,'; run;');
  put line;
run;

*-- run commands to copy datasets with 0 obs;

%include "&datfile";

*-- write commands to run fixNum macro for each file;

data _null_; set fname2 (where=(nobs>0));
  file "&datfile";
  length line $200.;
  line=cats('%fixnum(x.',memname,',xx.',memname,');');
  put line;
run;

*-- run the fixnum macro for each file;

%include "&datfile";         *-- include file with statements that run the macro; 

*-- cleanup;

proc datasets; delete temp: fname: ;
quit;

* END OF PROGRAM;
