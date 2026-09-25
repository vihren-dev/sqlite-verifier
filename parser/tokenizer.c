/* Reuse exact SQLite tokenizer and its contextual window-keyword lookahead. */
#include "sqlite3.c"

/* Keep the same lookahead rules as sqlite3RunParser, without preparing SQL. */
int native_token(const char *text, int previous, int *kind){
  int length = sqlite3GetToken((const unsigned char *)text, kind);
  if(*kind == TK_WINDOW) *kind = analyzeWindowKeyword((const u8 *)text + length);
  else if(*kind == TK_OVER) *kind = analyzeOverKeyword((const u8 *)text + length, previous);
  else if(*kind == TK_FILTER) *kind = analyzeFilterKeyword((const u8 *)text + length, previous);
  /* SQLite validates separators in sqlite3DequoteNumber, after tokenization.
  ** Preserve that lexical check without invoking its expression/codegen action. */
  if(*kind == TK_QNUMBER){
    int hex = text[0] == '0' && (text[1] == 'x' || text[1] == 'X');
    for(int i = 0; i < length; i++){
      if(text[i] != SQLITE_DIGIT_SEPARATOR) continue;
      int valid = i > 0 && i + 1 < length;
      if(valid && hex) valid = sqlite3Isxdigit(text[i-1]) && sqlite3Isxdigit(text[i+1]);
      else if(valid) valid = sqlite3Isdigit(text[i-1]) && sqlite3Isdigit(text[i+1]);
      if(!valid){ *kind = TK_ILLEGAL; break; }
    }
  }
  return length;
}

/* Native names are stable metadata; generated token numbers need not match. */
const char *native_name(int kind){
  switch(kind){
#include "token_names.inc"
    default: return "ILLEGAL";
  }
}

/* The fixed profile permits comments as SQLite does by default. */
int native_space(int kind){
  /* Older releases classify comments as TK_SPACE directly. */
#ifdef TK_COMMENT
  if(kind == TK_COMMENT) return 1;
#endif
  return kind == TK_SPACE;
}

/* Reject lexical errors before passing token numbers to Lemon. */
int native_illegal(int kind){ return kind == TK_ILLEGAL; }

/* SQLite permits the final statement's semicolon to be implicit at EOF. */
int native_semicolon(void){ return TK_SEMI; }
