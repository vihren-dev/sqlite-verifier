/* Public C API of the SQLite parser library.
**
** The library holds one parser for each grammar identity that the build made. A caller
** reads the metadata to find the grammar identity of a dialect, and then parses SQL with
** that identity. Each call returns a newly allocated JSON document; the caller releases
** it with sqlite_verifier_parser_free. The library makes no promise for concurrent calls:
** callers parse one text at a time.
*/
#ifndef SQLITE_VERIFIER_PARSER_LIBRARY_H
#define SQLITE_VERIFIER_PARSER_LIBRARY_H
#include <stddef.h>

/* The API version. The metadata document gives the same number as "api". */
#define SQLITE_VERIFIER_PARSER_API 1

/* The call made a document. A parse document can still report INPUT_ERROR or RESOURCE_LIMIT. */
#define SQLITE_VERIFIER_PARSER_OK 0
/* The library has no grammar with the given identity. The call made no document. */
#define SQLITE_VERIFIER_PARSER_UNKNOWN_GRAMMAR 1
/* The library could not allocate the document. The call made no document. */
#define SQLITE_VERIFIER_PARSER_NO_MEMORY 2

#if defined(__GNUC__)
#define SQLITE_VERIFIER_PARSER_EXPORT __attribute__((visibility("default")))
#else
#define SQLITE_VERIFIER_PARSER_EXPORT
#endif

/* Describe the library: API version, releases, dialects and grammars.
** On success, *document holds a JSON document of *length bytes. */
SQLITE_VERIFIER_PARSER_EXPORT int sqlite_verifier_parser_metadata(char **document, size_t *length);

/* Parse length bytes of SQL with the grammar whose identity is the NUL-terminated
** hexadecimal text grammar. sql can be NULL when length is 0. On success, *document
** holds a JSON document of *document_length bytes. */
SQLITE_VERIFIER_PARSER_EXPORT int sqlite_verifier_parser_parse(
  const char *grammar, const unsigned char *sql, size_t length,
  char **document, size_t *document_length);

/* Release a document from sqlite_verifier_parser_metadata or sqlite_verifier_parser_parse. */
SQLITE_VERIFIER_PARSER_EXPORT void sqlite_verifier_parser_free(char *document);
#endif
