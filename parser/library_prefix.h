/* Give the symbols of one grammar a unique prefix, so that one library can link several.
**
** The build compiles library_tokenizer.c and library_grammar.c once for each grammar
** identity, with GRAMMAR_PREFIX defined to that grammar's Lemon name. Both files include
** this header first, so the tokenizer functions, the Lemon functions and the grammar's
** parse function all carry the prefix.
*/
#ifndef SQLITE_VERIFIER_LIBRARY_PREFIX_H
#define SQLITE_VERIFIER_LIBRARY_PREFIX_H
#ifndef GRAMMAR_PREFIX
#error "GRAMMAR_PREFIX must name the grammar's Lemon prefix"
#endif
#define LIBRARY_JOIN_(left, right) left##right
#define LIBRARY_JOIN(left, right) LIBRARY_JOIN_(left, right)

#define native_token LIBRARY_JOIN(GRAMMAR_PREFIX, _native_token)
#define native_name LIBRARY_JOIN(GRAMMAR_PREFIX, _native_name)
#define native_space LIBRARY_JOIN(GRAMMAR_PREFIX, _native_space)
#define native_illegal LIBRARY_JOIN(GRAMMAR_PREFIX, _native_illegal)
#define native_semicolon LIBRARY_JOIN(GRAMMAR_PREFIX, _native_semicolon)
#define SyntaxAlloc LIBRARY_JOIN(GRAMMAR_PREFIX, Alloc)
#define SyntaxFree LIBRARY_JOIN(GRAMMAR_PREFIX, Free)
#define Syntax GRAMMAR_PREFIX
#define grammar_parse LIBRARY_JOIN(GRAMMAR_PREFIX, _parse)
#endif
