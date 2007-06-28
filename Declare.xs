#define PERL_DECL_PROT
#define PERL_CORE
#define PERL_NO_GET_CONTEXT
#include "/home/matthewt/tmp/perl-5.8.8/toke.c"
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#undef printf
#include <stdio.h>
#include <string.h>

#define LEX_NORMAL    10
#define LEX_INTERPNORMAL   9

/* placeholders for PL_check entries we wrap */

STATIC OP *(*dd_old_ck_rv2cv)(pTHX_ OP *op);
STATIC OP *(*dd_old_ck_nextstate)(pTHX_ OP *op);

/* flag to trigger removal of temporary declaree sub */

static int in_declare = 0;

/* replacement PL_check rv2cv entry */

STATIC OP *dd_ck_rv2cv(pTHX_ OP *o) {
  OP* kid;
  char* s;
  char tmpbuf[sizeof PL_tokenbuf];
  STRLEN len;
  HV *stash;
  HV* is_declarator;
  SV** is_declarator_pack_ref;
  HV* is_declarator_pack_hash;
  SV** is_declarator_flag_ref;
  char* cb_args[4];

  o = dd_old_ck_rv2cv(aTHX_ o); /* let the original do its job */

  if (in_declare) {
    cb_args[0] = NULL;
    call_argv("Devel::Declare::done_declare", G_VOID|G_DISCARD, cb_args);
    in_declare = 0;
    return o;
  }

  kid = cUNOPo->op_first;

  if (kid->op_type != OP_GV) /* not a GV so ignore */
    return o;

  if (PL_lex_state != LEX_NORMAL && PL_lex_state != LEX_INTERPNORMAL)
    return o; /* not lexing? */

  stash = GvSTASH(kGVOP_gv);

  /* printf("Checking GV %s -> %s\n", HvNAME(stash), GvNAME(kGVOP_gv)); */

  is_declarator = get_hv("Devel::Declare::declarators", FALSE);

  if (!is_declarator)
    return o;

  is_declarator_pack_ref = hv_fetch(is_declarator, HvNAME(stash),
                             strlen(HvNAME(stash)), FALSE);

  if (!is_declarator_pack_ref || !SvROK(*is_declarator_pack_ref))
    return o; /* not a hashref */

  is_declarator_pack_hash = (HV*) SvRV(*is_declarator_pack_ref);

  is_declarator_flag_ref = hv_fetch(is_declarator_pack_hash, GvNAME(kGVOP_gv),
                                strlen(GvNAME(kGVOP_gv)), FALSE);

  if (!is_declarator_flag_ref || !SvTRUE(*is_declarator_flag_ref))
    return o;

  s = PL_bufptr; /* copy the current buffer pointer */

  while (s < PL_bufend && isSPACE(*s)) s++;
  if (memEQ(s, PL_tokenbuf, strlen(PL_tokenbuf)))
    s += strlen(PL_tokenbuf);
  else
    return o;

  /* find next word */

  s = skipspace(s);

  /* 0 in arg 4 is allow_package - not trying that yet :) */

  s = scan_word(s, tmpbuf, sizeof tmpbuf, 0, &len);

  if (len) {
    cb_args[0] = HvNAME(stash);
    cb_args[1] = GvNAME(kGVOP_gv);
    cb_args[2] = tmpbuf;
    cb_args[3] = NULL;
    call_argv("Devel::Declare::init_declare", G_VOID|G_DISCARD, cb_args);
    in_declare = 1;
  }

  return o;
}

static int initialized = 0;

MODULE = Devel::Declare  PACKAGE = Devel::Declare

PROTOTYPES: DISABLE

void
setup()
  CODE:
  if (!initialized++) {
    dd_old_ck_rv2cv = PL_check[OP_RV2CV];
    PL_check[OP_RV2CV] = dd_ck_rv2cv;
  }

void
teardown()
  CODE:
  /* ensure we only uninit when number of teardown calls matches 
     number of setup calls */
  if (initialized && !--initialized) {
    PL_check[OP_RV2CV] = dd_old_ck_rv2cv;
  }