#ifndef PONG_PROTOCOL_H
#define PONG_PROTOCOL_H
#include <stddef.h>
#define PONG_MAX_LINE 192U
#define PONG_RESPONSE_SIZE 40U
/* Parse a complete line without LF. Return response length, or zero if invalid. */
size_t Pong_Respond(char *line, char response[PONG_RESPONSE_SIZE]);
#endif
