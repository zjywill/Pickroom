#ifndef PICKROOM_RAW_ENGINE_BRIDGE_H
#define PICKROOM_RAW_ENGINE_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *make;
    char *model;
    char *lens;
    int width;
    int height;
    double iso;
    double shutter;
    double aperture;
    double focal_length;
    int64_t timestamp;
} PRRawMetadata;

typedef struct {
    uint8_t *bytes;
    size_t byte_count;
    int width;
    int height;
    int bits_per_sample;
    int components;
    int format;
} PRRawImage;

const char *pr_raw_version(void);
int pr_raw_read_metadata(const char *path, PRRawMetadata *metadata);
void pr_raw_free_metadata(PRRawMetadata *metadata);

int pr_raw_extract_thumbnail(const char *path, PRRawImage *image);
int pr_raw_render_preview(const char *path, int half_size, PRRawImage *image);
void pr_raw_free_image(PRRawImage *image);

const char *pr_raw_error_message(int code);

#ifdef __cplusplus
}
#endif

#endif
