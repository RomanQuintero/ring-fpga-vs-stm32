#include "app_freertos.h"
#include "main.h"
#include "cmsis_os2.h"
#include "pong_protocol.h"
extern UART_HandleTypeDef huart3;
static osMessageQueueId_t rxQueue;
static uint8_t rxByte;
static volatile uint32_t rxEpoch;
typedef struct { uint32_t epoch; uint8_t byte; } RxItem;
static void BlinkTask(void *argument)
{
    (void)argument;
    for (;;) { HAL_GPIO_TogglePin(GPIOB, GPIO_PIN_0); osDelay(1000); }
}
static void PongTask(void *argument)
{
    (void)argument;
    char line[PONG_MAX_LINE + 1], response[PONG_RESPONSE_SIZE];
    size_t used = 0;
    int discard = 0;
    uint32_t epoch = 0;
    for (;;) {
        /* Retry reception after an overrun or failed restart. */
        if (huart3.RxState == HAL_UART_STATE_READY)
            (void)HAL_UART_Receive_IT(&huart3, &rxByte, 1);
        RxItem item;
        if (osMessageQueueGet(rxQueue, &item, NULL, 10) != osOK) continue;
        if (item.epoch != epoch) { epoch = item.epoch; discard = 1; used = 0; }
        if (item.byte == '\n') {
            if (!discard) {
                line[used] = '\0';
                size_t length = Pong_Respond(line, response);
                if (length) (void)HAL_UART_Transmit(&huart3, (uint8_t *)response, (uint16_t)length, 5);
            }
            used = 0;
            discard = 0;
        } else if (!discard) {
            if (used == PONG_MAX_LINE || item.byte == 0) { discard = 1; used = 0; }
            else line[used++] = (char)item.byte;
        }
    }
}
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance != USART3) return;
    RxItem item = { .epoch = rxEpoch, .byte = rxByte };
    if (osMessageQueuePut(rxQueue, &item, 0, 0) != osOK) ++rxEpoch;
    (void)HAL_UART_Receive_IT(huart, &rxByte, 1);
}
void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance != USART3) return;
    ++rxEpoch;
    if (huart->RxState == HAL_UART_STATE_READY) (void)HAL_UART_Receive_IT(huart, &rxByte, 1);
}
void MX_FREERTOS_Init(void)
{
    static const osThreadAttr_t pongAttributes = {
        .name = "pongTask", .stack_size = 2048, .priority = osPriorityAboveNormal
    };
    static const osThreadAttr_t blinkAttributes = {
        .name = "blinkTask", .stack_size = 512, .priority = osPriorityLow
    };
    rxQueue = osMessageQueueNew(512, sizeof(RxItem), NULL);
    if (rxQueue == NULL) Error_Handler();
    if (osThreadNew(PongTask, NULL, &pongAttributes) == NULL) Error_Handler();
    if (osThreadNew(BlinkTask, NULL, &blinkAttributes) == NULL) Error_Handler();
}
