/*
 * ECG Monitor Firmware - AD8232 & Arduino (ATmega328P / AVR)
 * 
 * Características:
 * - Amostragem periódica precisa a 500 Hz (2000 us) via Timer1 (CTC)
 *   com fallback para micros() em arquiteturas não-AVR.
 * - Leitura do conversor analógico-digital (A0) e pinos de Leads-Off (LO+, LO-).
 * - Fila circular (FIFO) protegida contra concorrência para transmissão serial sem atrasar o ADC.
 * - Protocolo estruturado v2:
 *     Inicialização: #ECG,VERSION=2,SAMPLE_RATE=500
 *     Amostras:      timestamp_us,adc,lead_off
 * - Taxa de comunicação: 115200 bps
 */

#include <Arduino.h>

const uint16_t SAMPLE_RATE_HZ = 500;
const uint32_t SERIAL_BAUD = 115200;

const int PIN_ANALOG_INPUT = A0;
const int PIN_LO_PLUS = 10;
const int PIN_LO_MINUS = 11;

// Estrutura de pacote para a fila de envio
struct SamplePacket {
  uint32_t timestamp_us;
  uint16_t adc;
  uint8_t  lead_off;
};

// Capacidade do buffer circular (potência de 2)
const uint8_t QUEUE_CAPACITY = 64;
static volatile SamplePacket sampleQueue[QUEUE_CAPACITY];
static volatile uint8_t queueHead = 0;
static volatile uint8_t queueTail = 0;
static volatile uint32_t droppedSamples = 0;

#if defined(__AVR_ATmega328P__) || defined(__AVR_ATmega168__) || defined(__AVR__)
#define USE_AVR_TIMER1 1
#else
#define USE_AVR_TIMER1 0
#endif

// Coleta a amostra no instante exato e insere na fila circular
static inline void acquireSample() {
  uint32_t nowUs = micros();
  
  // Detecção de Leads-Off
  uint8_t lo = 0;
#if defined(PORTB) && defined(PINB)
  // Leitura direta de porta para o Uno/Nano (Pinos 10 e 11 = PB2 e PB3)
  if (PINB & ((1 << PB2) | (1 << PB3))) {
    lo = 1;
  }
#else
  if (digitalRead(PIN_LO_PLUS) == HIGH || digitalRead(PIN_LO_MINUS) == HIGH) {
    lo = 1;
  }
#endif

  int adcVal = analogRead(PIN_ANALOG_INPUT);

  uint8_t nextHead = (queueHead + 1) & (QUEUE_CAPACITY - 1);
  if (nextHead != queueTail) {
    sampleQueue[queueHead].timestamp_us = nowUs;
    sampleQueue[queueHead].adc = (uint16_t)adcVal;
    sampleQueue[queueHead].lead_off = lo;
    queueHead = nextHead;
  } else {
    // Fila cheia: registra perda sem travar o timer
    droppedSamples++;
  }
}

#if USE_AVR_TIMER1
// Interrupção do Timer 1 em modo CTC a 500 Hz
// Clock = 16 MHz, Prescaler = 64 -> F_timer = 250 kHz
// OCR1A = (16000000 / (64 * 500)) - 1 = 499
ISR(TIMER1_COMPA_vect) {
  acquireSample();
}

static void setupTimer1() {
  cli(); // Desativa interrupções para configuração
  
  TCCR1A = 0;
  TCCR1B = 0;
  TCNT1  = 0;
  
  // WGM12 = 1 (Modo CTC), CS11 e CS10 = 1 (Prescaler 64)
  OCR1A = 499;
  TCCR1B |= (1 << WGM12) | (1 << CS11) | (1 << CS10);
  
  // Habilita interrupção de comparação OCR1A
  TIMSK1 |= (1 << OCIE1A);
  
  sei(); // Reativa interrupções
}
#else
static unsigned long lastSampleMicros = 0;
const unsigned long SAMPLE_INTERVAL_US = 1000000UL / SAMPLE_RATE_HZ;
#endif

void setup() {
  Serial.begin(SERIAL_BAUD);
  pinMode(PIN_LO_PLUS, INPUT);
  pinMode(PIN_LO_MINUS, INPUT);
  pinMode(PIN_ANALOG_INPUT, INPUT);

  // Aguarda inicialização da Serial
  while (!Serial && millis() < 1200) { }

  // Cabeçalho de identificação do protocolo v2
  Serial.println(F("#ECG,VERSION=2,SAMPLE_RATE=500"));

#if USE_AVR_TIMER1
  setupTimer1();
#else
  lastSampleMicros = micros();
#endif
}

void loop() {
#if !USE_AVR_TIMER1
  // Polling via micros() caso não seja AVR
  unsigned long currentMicros = micros();
  if ((unsigned long)(currentMicros - lastSampleMicros) >= SAMPLE_INTERVAL_US) {
    lastSampleMicros += SAMPLE_INTERVAL_US;
    if ((unsigned long)(currentMicros - lastSampleMicros) > SAMPLE_INTERVAL_US) {
      lastSampleMicros = currentMicros;
    }
    acquireSample();
  }
#endif

  // Esvazia a fila transmitindo pela serial sem travar a amostragem
  while (queueTail != queueHead) {
    SamplePacket pkt;
    
#if USE_AVR_TIMER1
    uint8_t oldSREG = SREG;
    cli();
#endif
    pkt = sampleQueue[queueTail];
    queueTail = (queueTail + 1) & (QUEUE_CAPACITY - 1);
#if USE_AVR_TIMER1
    SREG = oldSREG;
#endif

    // Transmissão no protocolo v2: timestamp_us,adc,lead_off
    Serial.print(pkt.timestamp_us);
    Serial.print(',');
    Serial.print(pkt.adc);
    Serial.print(',');
    Serial.println(pkt.lead_off);
  }
}
