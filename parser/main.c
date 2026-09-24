/* File-to-CST shell: no schema execution, filesystem SQL operations, or proofs. */
#include "runtime.h"
#include "syntax.h"

/* Map token identities explicitly instead of assuming regenerated number stability. */
static int parser_token(int kind){
  switch(kind){
#include "token_map.inc"
    default: return 0;
  }
}

/* Validate UTF-8 and reject NUL: SQLite's C API otherwise silently truncates input. */
static int utf8_valid(const unsigned char *text, int size){
  for(int i = 0; i < size;){
    unsigned c = text[i++], value;
    int tail;
    if(c == 0) return 0;
    if(c < 128) continue;
    if(c >= 194 && c <= 223){ tail = 1; value = c & 31; }
    else if(c >= 224 && c <= 239){ tail = 2; value = c & 15; }
    else if(c >= 240 && c <= 244){ tail = 3; value = c & 7; }
    else return 0;
    int length = tail;
    if(i + tail > size) return 0;
    while(tail--){ c = text[i++]; if((c & 192) != 128) return 0; value = (value << 6) | (c & 63); }
    if((length == 2 && value < 2048) || (length == 3 && value < 65536)
       || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) return 0;
  }
  return 1;
}

/* Emit deterministic JSON: symbols come exclusively from the pinned grammar. */
static void output(Context *ctx){
  if(ctx->error || !ctx->accepted){
    printf("{\"status\":\"%s\",\"offset\":%d}\n",
           ctx->error == 2 ? "RESOURCE_LIMIT" : "INPUT_ERROR", ctx->offset);
    return;
  }
  printf("{\"status\":\"PARSED\",\"profile\":\"3.51.0\",\"root\":%d,\"nodes\":[", ctx->root);
  for(int i = 0; i < ctx->count; i++){
    Node *node = &ctx->nodes[i];
    printf("%s{\"symbol\":\"%s\",\"start\":%d,\"end\":%d,\"children\":[",
           i ? "," : "", node->symbol, node->start, node->end);
    for(int j = 0; j < node->count; j++) printf("%s%d", j ? "," : "", node->children[j]);
    printf("]}");
  }
  puts("]}");
}

/* Recognize the entire script, injecting SQLite's final semicolon when necessary. */
static void parse(Context *ctx, const char *text, int size){
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

/* Bound input and allocation before exposing the native tokenizer to user bytes. */
int main(int argc, char **argv){
  Context ctx = {0};
  if(argc != 2){ fputs("usage: sqlite-parser SQL_FILE\n", stderr); return 2; }
  FILE *file = fopen(argv[1], "rb");
  if(!file){ perror("SQL_FILE"); return 2; }
  const int maximum = 1024 * 1024;
  char *text = calloc((size_t)maximum + 4, 1);
  if(!text){ fclose(file); return 2; }
  int size = (int)fread(text, 1, (size_t)maximum + 1, file);
  int io_error = ferror(file);
  fclose(file);
  if(size > maximum || io_error) ctx.error = 2;
  else if(!utf8_valid((const unsigned char *)text, size)) ctx.error = 1;
  else parse(&ctx, text, size);
  output(&ctx);
  for(int i = 0; i < ctx.count; i++) free(ctx.nodes[i].children);
  free(ctx.nodes);
  free(text);
  return ctx.error || !ctx.accepted ? 1 : 0;
}
