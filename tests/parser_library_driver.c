/* Drive the parser library from one process, for the parser library checks.
**
** "driver LIBRARY metadata" writes the metadata document to standard output.
** "driver LIBRARY parse INPUTS OUTPUT GRAMMAR..." parses each record of INPUTS with each
** GRAMMAR in turn and writes, for each parse, the 4-byte little-endian result code, the
** 4-byte document length and the document. Records are a 4-byte length and the bytes.
**
** It loads the library with dlopen from the given path only, as the verifier will. The
** sanitizer job builds it with the sanitizers, and it frees every document and input, so
** that a leak report points at the library.
*/
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int (*Metadata)(char **document, size_t *length);
typedef int (*Parse)(const char *grammar, const unsigned char *sql, size_t length,
                     char **document, size_t *document_length);
typedef void (*Release)(char *document);

/* Read one record; return 0 at the end of the file and -1 for a malformed file. */
static int read_record(FILE *file, unsigned char **data, uint32_t *size){
  unsigned char prefix[4];
  size_t got = fread(prefix, 1, 4, file);
  if(got == 0) return 0;
  if(got != 4) return -1;
  *size = (uint32_t)prefix[0] | (uint32_t)prefix[1] << 8 | (uint32_t)prefix[2] << 16 | (uint32_t)prefix[3] << 24;
  *data = malloc(*size ? *size : 1);
  if(!*data || fread(*data, 1, *size, file) != *size){ free(*data); return -1; }
  return 1;
}

/* Write a 4-byte little-endian number. */
static void write_number(FILE *file, uint32_t value){
  unsigned char bytes[4] = {value & 255, value >> 8 & 255, value >> 16 & 255, value >> 24 & 255};
  fwrite(bytes, 1, 4, file);
}

/* Parse every input with every grammar, in that order, and write the results. */
static int parse_all(Parse parse, Release release, const char *inputs, const char *output,
                     char **grammars, int count){
  FILE *results = fopen(output, "wb");
  if(!results){ perror(output); return 2; }
  for(int g = 0; g < count; g++){
    FILE *file = fopen(inputs, "rb");
    if(!file){ perror(inputs); fclose(results); return 2; }
    unsigned char *sql;
    uint32_t size;
    int status;
    while((status = read_record(file, &sql, &size)) == 1){
      char *document = NULL;
      size_t length = 0;
      int code = parse(grammars[g], sql, size, &document, &length);
      write_number(results, (uint32_t)code);
      write_number(results, (uint32_t)length);
      if(document) fwrite(document, 1, length, results);
      release(document);
      free(sql);
    }
    fclose(file);
    if(status < 0){ fprintf(stderr, "%s: malformed input record\n", inputs); fclose(results); return 2; }
  }
  return fclose(results) ? 2 : 0;
}

int main(int argc, char **argv){
  if(argc < 3 || (strcmp(argv[2], "metadata") && (strcmp(argv[2], "parse") || argc < 6))){
    fputs("usage: driver LIBRARY metadata | driver LIBRARY parse INPUTS OUTPUT GRAMMAR...\n", stderr);
    return 2;
  }
  void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if(!library){ fprintf(stderr, "%s\n", dlerror()); return 2; }
  Metadata metadata = (Metadata)dlsym(library, "sqlite_verifier_parser_metadata");
  Parse parse = (Parse)dlsym(library, "sqlite_verifier_parser_parse");
  Release release = (Release)dlsym(library, "sqlite_verifier_parser_free");
  if(!metadata || !parse || !release){ fputs("The library lacks a public API function\n", stderr); return 2; }
  int result = 0;
  if(!strcmp(argv[2], "metadata")){
    char *document = NULL;
    size_t length = 0;
    result = metadata(&document, &length);
    if(!result) fwrite(document, 1, length, stdout);
    release(document);
  }else{
    result = parse_all(parse, release, argv[3], argv[4], argv + 5, argc - 5);
  }
  dlclose(library);
  return result;
}
