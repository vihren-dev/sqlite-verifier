/* The Lemon parser of one grammar in the parser library, and its parse loop.
**
** The parse loop feeds the release's tokens to the generated parser and adds SQLite's
** final semicolon when the text has none. library.c checks the
** input and writes the document; this file only builds the syntax tree in a Context.
*/
#include "library_prefix.h"
#include "runtime.h"
#include "syntax.c"

/* Map token identities explicitly instead of assuming regenerated number stability. */
static int parser_token(int kind){
  switch(kind){
#include "token_map.inc"
    default: return 0;
  }
}

/* Build the syntax tree of a checked, NUL-terminated text of size bytes into ctx. */
void grammar_parse(Context *ctx, const char *text, int size){
  void *parser = SyntaxAlloc(malloc);
  int previous = -1;
  if(!parser){ ctx->error = 2; return; }
  while(ctx->offset < size && !ctx->error){
    int kind;
    int length = native_token(text + ctx->offset, previous, &kind);
    if(length <= 0 || native_illegal(kind)){ ctx->error = 1; break; }
    if(!native_space(kind)){
      Node token = {native_name(kind), ctx->offset, ctx->offset + length, 0, NULL};
      int index = append(ctx, token);
      if(!ctx->error) Syntax(parser, parser_token(kind), index, ctx);
      previous = kind;
    }
    if(!ctx->error) ctx->offset += length;
  }
  if(!ctx->error && previous != native_semicolon()){
    Node token = {"SEMI", size, size, 0, NULL};
    int index = append(ctx, token);
    if(!ctx->error) Syntax(parser, P_SEMI, index, ctx);
  }
  if(!ctx->error) Syntax(parser, 0, 0, ctx);
  SyntaxFree(parser, free);
}
