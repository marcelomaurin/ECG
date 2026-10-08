/* Maurinsoft ECG - Nano classic (ATmega328P, 16 MHz) + AD8232.
 * ADC0/A0, LO+ D10, LO- D11. AD8232 supply/SDN: 3.3 V, NOT 5 V.
 * Timer1 Compare B triggers the ADC at 500 Hz. Timer0/millis unchanged.
 * No digital filtering on the Nano: keep the acquired samples intact.
 * Protocol v3 @115200 8N1: sequence,adc,lead_off\r\n
 * Sequence advances even on buffer overflow; the receiver detects lost samples.
 * See docs/NANO_AD8232.md before wiring or uploading.
 */
#include <Arduino.h>
#include <avr/interrupt.h>
#include <util/atomic.h>
#include <stdio.h>

#if !defined(__AVR_ATmega328P__) || F_CPU != 16000000UL
#error "Select Arduino Nano / ATmega328P at 16 MHz (classic Nano)."
#endif

const uint16_t SAMPLE_RATE_HZ = 500;
const uint32_t SERIAL_BAUD = 115200;
const uint8_t PIN_LO_PLUS = 10;
const uint8_t PIN_LO_MINUS = 11;
const uint8_t BUFFER_SIZE = 64; // 63 usable slots: 126 ms at 500 Hz
const uint8_t BUFFER_MASK = BUFFER_SIZE - 1;
const uint16_t TIMER_TOP = F_CPU / 8UL / SAMPLE_RATE_HZ - 1;

struct ECGFrame {
  uint32_t sequence;
  uint16_t adc;
  uint8_t leadOff;
};
volatile ECGFrame frames[BUFFER_SIZE];
volatile uint8_t writeIndex = 0;
volatile uint8_t readIndex = 0;
volatile uint32_t sampleSequence = 0;
volatile uint32_t droppedSamples = 0;

ISR(ADC_vect) {
  const uint16_t adc = ADC;
  // Clear the trigger flag so the next compare event produces a rising edge.
  TIFR1 = _BV(OCF1B);
  const uint32_t sequence = sampleSequence++;
  const uint8_t leadOff = (PINB & (_BV(PB2) | _BV(PB3))) ? 1 : 0;
  const uint8_t next = (writeIndex + 1) & BUFFER_MASK;
  if (next == readIndex) {
    ++droppedSamples; // drop newest, never overwrite a frame being transmitted
    return;
  }
  frames[writeIndex].sequence = sequence;
  frames[writeIndex].adc = adc;
  frames[writeIndex].leadOff = leadOff;
  writeIndex = next;
}

void sendHeader() {
  Serial.println(F("#ECG,VERSION=3,SAMPLE_RATE=500,ADC_BITS=10,VREF_MV=5000"));
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  pinMode(A0, INPUT);
  pinMode(PIN_LO_PLUS, INPUT); // no 5 V pull-ups on AD8232 outputs
  pinMode(PIN_LO_MINUS, INPUT);
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.println(F("#START"));
  sendHeader();

  // Default AVCC reference (~5 V), ADC0. Do not connect 3.3 V to AREF.
  ADMUX = _BV(REFS0);
  ADCSRB = 0;
  DIDR0 |= _BV(ADC0D);
  ADCSRA = _BV(ADEN) | _BV(ADPS2) | _BV(ADPS1) | _BV(ADPS0);
  // Warm up the ADC once; discard the longer first conversion.
  ADCSRA |= _BV(ADSC);
  while (ADCSRA & _BV(ADSC)) { }
  (void)ADC;
  ADCSRA |= _BV(ADIF);

  ATOMIC_BLOCK(ATOMIC_RESTORESTATE) {
    TCCR1A = 0; // OC1A/OC1B disconnected: D10 remains a leads-off INPUT
    TCCR1B = 0;
    TIMSK1 = 0;
    TCNT1 = 0;
    OCR1A = TIMER_TOP;
    OCR1B = TIMER_TOP;
    TIFR1 = _BV(OCF1A) | _BV(OCF1B) | _BV(TOV1);
    ADCSRB = _BV(ADTS2) | _BV(ADTS0); // 101: Timer1 Compare Match B
    ADCSRA = _BV(ADEN) | _BV(ADATE) | _BV(ADIE) | _BV(ADIF) |
      _BV(ADPS2) | _BV(ADPS1) | _BV(ADPS0); // ADC clock = 125 kHz
    // ADATE starts conversions on timer edges; no extra software ADSC conversion.
    TCCR1B = _BV(WGM12) | _BV(CS11); // CTC, prescaler 8
  }
}

void loop() {
  static char line[32];
  static uint8_t pendingLength = 0;
  static uint32_t lastHeaderMs = 0;
  static uint32_t lastRequestMs = 0;
  const uint32_t now = millis();
  bool headerRequested = false;
  // Bounded receive work; '?' lets the PC reconnect without a board reset.
  for (uint8_t i = 0; i < 8 && Serial.available(); ++i) {
    if (Serial.read() == '?' && now - lastRequestMs >= 250) {
      headerRequested = true;
      lastRequestMs = now;
    }
  }
  if (headerRequested || now - lastHeaderMs >= 5000) {
    sendHeader();
    uint32_t lost;
    ATOMIC_BLOCK(ATOMIC_RESTORESTATE) { lost = droppedSamples; }
    Serial.print(F("#STAT,DROPPED="));
    Serial.println(lost);
    lastHeaderMs = now;
  }
  if (pendingLength == 0) {
    ECGFrame frame;
    bool haveFrame = false;
    ATOMIC_BLOCK(ATOMIC_RESTORESTATE) {
      if (readIndex != writeIndex) {
        frame.sequence = frames[readIndex].sequence;
        frame.adc = frames[readIndex].adc;
        frame.leadOff = frames[readIndex].leadOff;
        readIndex = (readIndex + 1) & BUFFER_MASK;
        haveFrame = true;
      }
    }
    if (haveFrame) {
      pendingLength = snprintf(line, sizeof(line), "%lu,%u,%u\r\n",
        (unsigned long)frame.sequence, frame.adc, frame.leadOff);
      digitalWrite(LED_BUILTIN, frame.leadOff ? HIGH : LOW);
    }
  }
  if (pendingLength && Serial.availableForWrite() >= pendingLength) {
    Serial.write((const uint8_t*)line, pendingLength);
    pendingLength = 0;
  }
}
