#include "pong_protocol.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int ParseInteger(const char *text, int32_t *value)
{
    int negative = (*text == '-');
    if (negative) ++text;
    if (*text == '\0') return 0;
    uint32_t number = 0;
    const uint32_t limit = negative ? 2147483648U : 2147483647U;
    for (; *text; ++text) {
        if (*text < '0' || *text > '9') return 0;
        uint32_t digit = (uint32_t)(*text - '0');
        if (number > (limit - digit) / 10U) return 0;
        number = number * 10U + digit;
    }
    *value = negative ? (int32_t)(-(int64_t)number) : (int32_t)number;
    return 1;
}

size_t Pong_Respond(char *line, char response[PONG_RESPONSE_SIZE])
{
    size_t length = strlen(line);
    if (length > PONG_MAX_LINE) return 0;
    if (length && line[length - 1] == '\r') line[--length] = '\0';
    char *fields[13];
    unsigned count = 1;
    fields[0] = line;
    for (char *p = line; *p; ++p) {
        if (*p == ',') {
            if (count == 13) return 0;
            *p = '\0';
            fields[count++] = p + 1;
        }
    }
    if (count != 13 || strcmp(fields[0], "STATE") || strcmp(fields[1], "1") ||
        (strcmp(fields[3], "L") && strcmp(fields[3], "R"))) return 0;

    /* Keep the tick as text; validate the signed 64-bit nonnegative range. */
    const char *tick = fields[2];
    if (!*tick) return 0;
    for (const char *p = tick; *p; ++p) if (*p < '0' || *p > '9') return 0;
    while (*tick == '0' && tick[1]) ++tick;
    size_t digits = strlen(tick);
    if (digits > 19 || (digits == 19 && strcmp(tick, "9223372036854775807") > 0)) return 0;

    int32_t values[9];
    for (unsigned i = 0; i < 9; ++i) if (!ParseInteger(fields[i + 4], &values[i])) return 0;
    if (values[6] <= 0 || values[7] <= 0 || values[8] <= 0 || values[8] > values[7]) return 0;
    int64_t difference = (int64_t)values[1] - values[4];
    const char *action = difference < -6 ? "UP" : difference > 6 ? "DOWN" : "STAY";
    int written = snprintf(response, PONG_RESPONSE_SIZE, "ACT,1,%s,%s\n", tick, action);
    return written > 0 && written < (int)PONG_RESPONSE_SIZE ? (size_t)written : 0;
}
