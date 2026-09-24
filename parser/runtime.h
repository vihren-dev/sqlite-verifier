/* Shared syntax-tree representation; indexes keep generated reductions small. */
#ifndef SQLITE_VERIFIER_RUNTIME_H
#define SQLITE_VERIFIER_RUNTIME_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* One terminal/nonterminal and its original UTF-8 byte span. */
typedef struct {
  const char *symbol;
  int start, end, count;
  int *children;
} Node;

/* A bounded parse owns all nodes until deterministic JSON emission. */
typedef struct {
  Node *nodes;
  int count, capacity, offset, error, accepted, root;
} Context;

/* Allocation failure is a resource diagnostic, never syntax acceptance. */
static inline int append(Context *ctx, Node node){
  if(ctx->error) return -1;
  if(ctx->count >= 200000){ ctx->error = 2; return -1; }
  if(ctx->count == ctx->capacity){
    int capacity = ctx->capacity ? ctx->capacity * 2 : 256;
    Node *nodes = realloc(ctx->nodes, (size_t)capacity * sizeof(Node));
    if(!nodes){ ctx->error = 2; return -1; }
    ctx->nodes = nodes;
    ctx->capacity = capacity;
  }
  ctx->nodes[ctx->count] = node;
  return ctx->count++;
}

/* Retain all reduction children, including punctuation and empty productions. */
static inline int branch(Context *ctx, const char *symbol, int count, int *children){
  Node node = {symbol, ctx->offset, ctx->offset, count, NULL};
  if(ctx->error) return -1;
  if(count){
    node.children = malloc((size_t)count * sizeof(int));
    if(!node.children){ctx->error = 2; return -1;}
    memcpy(node.children, children, (size_t)count * sizeof(int));
    node.start = ctx->nodes[children[0]].start;
    node.end = ctx->nodes[children[count - 1]].end;
  }
  int result = append(ctx, node);
  if(result < 0) free(node.children);
  return result;
}

/* Tokenizer interface uses upstream token numbers without exposing SQLite internals. */
int native_token(const char *text, int previous, int *kind);
const char *native_name(int kind);
int native_space(int kind);
int native_illegal(int kind);
int native_semicolon(void);

/* Generated Lemon parser API; its semantic values are node indexes. */
void *SyntaxAlloc(void *(*allocator)(size_t));
void Syntax(void *parser, int kind, int node, Context *ctx);
void SyntaxFree(void *parser, void (*release)(void *));
#endif
