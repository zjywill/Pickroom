#include <LibRaw/libraw.h>
#include "RawEngineBridge.h"

#include <stdlib.h>
#include <string.h>

static char *pr_duplicate_string(const char *value) {
    if (!value || value[0] == '\0') {
        return NULL;
    }

    size_t length = strlen(value) + 1;
    char *copy = (char *)malloc(length);
    if (copy) {
        memcpy(copy, value, length);
    }
    return copy;
}

static int pr_copy_image(libraw_processed_image_t *source, PRRawImage *image) {
    if (!source || !image || source->data_size == 0) {
        return LIBRAW_UNSPECIFIED_ERROR;
    }

    image->bytes = (uint8_t *)malloc(source->data_size);
    if (!image->bytes) {
        return LIBRAW_UNSUFFICIENT_MEMORY;
    }

    memcpy(image->bytes, source->data, source->data_size);
    image->byte_count = source->data_size;
    image->width = source->width;
    image->height = source->height;
    image->bits_per_sample = source->bits;
    image->components = source->colors;
    image->format = source->type;
    return LIBRAW_SUCCESS;
}

const char *pr_raw_version(void) {
    return libraw_version();
}

int pr_raw_read_metadata(const char *path, PRRawMetadata *metadata) {
    if (!path || !metadata) {
        return LIBRAW_UNSPECIFIED_ERROR;
    }

    memset(metadata, 0, sizeof(PRRawMetadata));
    libraw_data_t *raw = libraw_init(0);
    if (!raw) {
        return LIBRAW_UNSUFFICIENT_MEMORY;
    }

    int result = libraw_open_file(raw, path);
    if (result == LIBRAW_SUCCESS) {
        metadata->make = pr_duplicate_string(raw->idata.make);
        metadata->model = pr_duplicate_string(raw->idata.model);
        metadata->lens = pr_duplicate_string(raw->lens.Lens);
        metadata->width = raw->sizes.width;
        metadata->height = raw->sizes.height;
        metadata->iso = raw->other.iso_speed;
        metadata->shutter = raw->other.shutter;
        metadata->aperture = raw->other.aperture;
        metadata->focal_length = raw->other.focal_len;
        metadata->timestamp = (int64_t)raw->other.timestamp;
    }

    libraw_close(raw);
    return result;
}

void pr_raw_free_metadata(PRRawMetadata *metadata) {
    if (!metadata) {
        return;
    }

    free(metadata->make);
    free(metadata->model);
    free(metadata->lens);
    memset(metadata, 0, sizeof(PRRawMetadata));
}

int pr_raw_extract_thumbnail(const char *path, PRRawImage *image) {
    if (!path || !image) {
        return LIBRAW_UNSPECIFIED_ERROR;
    }

    memset(image, 0, sizeof(PRRawImage));
    libraw_data_t *raw = libraw_init(0);
    if (!raw) {
        return LIBRAW_UNSUFFICIENT_MEMORY;
    }

    int result = libraw_open_file(raw, path);
    if (result == LIBRAW_SUCCESS) {
        result = libraw_unpack_thumb(raw);
    }

    if (result == LIBRAW_SUCCESS) {
        int image_error = LIBRAW_SUCCESS;
        libraw_processed_image_t *processed = libraw_dcraw_make_mem_thumb(raw, &image_error);
        if (!processed) {
            result = image_error;
        } else {
            result = pr_copy_image(processed, image);
            libraw_dcraw_clear_mem(processed);
        }
    }

    libraw_close(raw);
    return result;
}

int pr_raw_render_preview(const char *path, int half_size, PRRawImage *image) {
    if (!path || !image) {
        return LIBRAW_UNSPECIFIED_ERROR;
    }

    memset(image, 0, sizeof(PRRawImage));
    libraw_data_t *raw = libraw_init(0);
    if (!raw) {
        return LIBRAW_UNSUFFICIENT_MEMORY;
    }

    raw->params.use_camera_wb = 1;
    raw->params.use_auto_wb = 0;
    raw->params.output_color = 1;
    raw->params.output_bps = 8;
    raw->params.half_size = half_size ? 1 : 0;
    raw->params.user_qual = half_size ? 0 : 3;
    raw->params.no_auto_bright = 0;

    int result = libraw_open_file(raw, path);
    if (result == LIBRAW_SUCCESS) {
        result = libraw_unpack(raw);
    }
    if (result == LIBRAW_SUCCESS) {
        result = libraw_dcraw_process(raw);
    }

    if (result == LIBRAW_SUCCESS) {
        int image_error = LIBRAW_SUCCESS;
        libraw_processed_image_t *processed = libraw_dcraw_make_mem_image(raw, &image_error);
        if (!processed) {
            result = image_error;
        } else {
            result = pr_copy_image(processed, image);
            libraw_dcraw_clear_mem(processed);
        }
    }

    libraw_close(raw);
    return result;
}

void pr_raw_free_image(PRRawImage *image) {
    if (!image) {
        return;
    }

    free(image->bytes);
    memset(image, 0, sizeof(PRRawImage));
}

const char *pr_raw_error_message(int code) {
    return libraw_strerror(code);
}
