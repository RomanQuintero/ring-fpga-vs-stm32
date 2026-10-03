#include "pong_protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static void Check(const char *input, const char *expected)
{
    char line[256], response[PONG_RESPONSE_SIZE];
    memcpy(line, input, strlen(input) + 1);
    size_t size = Pong_Respond(line, response);
    if (expected) { assert(size == strlen(expected)); assert(strcmp(response, expected) == 0); }
    else assert(size == 0);
}
int main(void)
{
    Check("STATE,1,42,L,424,271,-5,3,180,200,960,480,80", "ACT,1,42,DOWN\n");
    Check("STATE,1,42,R,424,173,-5,3,180,200,960,480,80\r", "ACT,1,42,UP\n");
    Check("STATE,1,42,L,424,174,-5,3,180,200,960,480,80", "ACT,1,42,STAY\n");
    Check("STATE,1,42,L,424,186,-5,3,180,200,960,480,80", "ACT,1,42,STAY\n");
    Check("STATE,1,0,L,424,187,-5,3,180,200,960,480,80", "ACT,1,0,DOWN\n");
    Check("STATE,1,9223372036854775807,L,424,271,-5,3,180,200,960,480,80", "ACT,1,9223372036854775807,DOWN\n");
    Check("STATE,1,9223372036854775808,L,424,271,-5,3,180,200,960,480,80", NULL);
    Check("STATE,1,-1,L,424,271,-5,3,180,200,960,480,80", NULL);
    Check("STATE,2,42,L,424,271,-5,3,180,200,960,480,80", NULL);
    Check("STATE,1,42,X,424,271,-5,3,180,200,960,480,80", NULL);
    Check("STATE,1,42,L,424,271,-5,3,180,200,960,480,80,1", NULL);
    Check("STATE,1,42,L,424,271,-5,3,180,200,960,480", NULL);
    Check("STATE,1,42,L,424,271,-5,3,,200,960,480,80", NULL);
    Check("STATE,1,42,L,424,271,-5,3, 180,200,960,480,80", NULL);
    Check("STATE,1,42,L,424,271,-5,3,2147483648,200,960,480,80", NULL);
    Check("STATE,1,42,L,424,271,-5,3,180,200,960,0,80", NULL);
    Check("STATE,1,42,L,424,271,-5,3,180,200,960,480,481", NULL);
    char oversized[194];
    memset(oversized, '0', 193); oversized[193] = '\0';
    Check(oversized, NULL);
    puts("18 protocol checks passed");
    return 0;
}
