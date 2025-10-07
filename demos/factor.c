/*
 * Minimal factor utility derived from the BSD factor(6) program.
 * Original copyright (c) 1989, 1993
 *  The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * This version has been lightly adapted (e.g., removed locale handling)
 * to compile cleanly under Emscripten/WASI.
 */

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

static void factor(uint64_t n) {
    if (n == 0) {
        puts("0: 0");
        return;
    }

    printf("%" PRIu64 ":", n);
    if (n == 1) {
        putchar(' ');
        puts("1");
        return;
    }

    while ((n & 1u) == 0) {
        printf(" %u", 2u);
        n >>= 1u;
    }

    for (uint64_t f = 3; f * f <= n; f += 2) {
        while (n % f == 0) {
            printf(" %" PRIu64, f);
            n /= f;
        }
    }

    if (n > 1) {
        printf(" %" PRIu64, n);
    }
    putchar('\n');
}

int main(void) {
    char buf[256];

    while (fgets(buf, sizeof buf, stdin)) {
        char *end = NULL;
        errno = 0;
        uint64_t value = strtoull(buf, &end, 10);
        if (errno != 0 || (end && !isspace((unsigned char)*end) && *end != '\0')) {
            fprintf(stderr, "factor: invalid input: %s", buf);
            continue;
        }
        factor(value);
    }

    if (ferror(stdin)) {
        perror("factor: read error");
        return 1;
    }
    return 0;
}
