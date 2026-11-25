#pragma once
#include <stdbool.h>
#include <stdint.h>

// Callbacks run synchronously on the calling thread. Paths are borrowed for one call.
bool crumbs_search_files(const char *term, const char *directory, void *context,
                         bool (*cancelled)(void *),
                         void (*append)(void *, const char *path, bool folder));

bool crumbs_inside_media_library(const char *path);
uint64_t crumbs_index_revision(void);
bool crumbs_index_ready(void);
void crumbs_stop_file_index(void);
void crumbs_start_file_index(const char *cache);
bool crumbs_recent_files(const char *predicate, const char *scope, void *context,
                         bool (*cancelled)(void *),
                         void (*append)(void *, const char *path, bool folder));
