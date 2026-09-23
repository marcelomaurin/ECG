/*
 * ECG Monitor Firmware - AD8232 & Arduino
 * 
 * Tarefas 3, 4 e 5:
 * - Temporização sem delay() via micros() a 500 Hz (2000 us)
 * - Protocolo serial estruturado: timestamp_us,adc,lead_off
 * - Velocidade serial de 115200 bps
 */

const uint16_t SAMPLE_RATE_HZ = 500;
const unsigned long SAMPLE_INTERVAL_US = 1000000UL / SAMPLE_RATE_HZ;
const uint32_t SERIAL_BAUD = 115200;

const int PIN_ANALOG_INPUT = A0;
const int PIN_LO_PLUS = 10;
const int PIN_LO_MINUS = 11;

unsigned long lastSampleMicros = 0;

void setup() {
  Serial.begin(SERIAL_BAUD);
  pinMode(PIN_LO_PLUS, INPUT);
  pinMode(PIN_LO_MINUS, INPUT);

  // Aguarda estabilização inicial da serial
  while (!Serial && millis() < 1000) { }

  // Cabeçalho de identificação do protocolo estruturado v2
  Serial.println(F("#ECG,VERSION=2,SAMPLE_RATE=500"));

  lastSampleMicros = micros();
}

void loop() {
  unsigned long currentMicros = micros();

  // Executa amostragem estritamente no intervalo de 2000 us (500 Hz)
  if ((unsigned long)(currentMicros - lastSampleMicros) >= SAMPLE_INTERVAL_US) {
    lastSampleMicros += SAMPLE_INTERVAL_US;

    // Resincronização se houver atraso acumulado
    if ((unsigned long)(currentMicros - lastSampleMicros) > SAMPLE_INTERVAL_US) {
      lastSampleMicros = currentMicros;
    }

    uint8_t leadOff = 0;
    if ((digitalRead(PIN_LO_PLUS) == HIGH) || (digitalRead(PIN_LO_MINUS) == HIGH)) {
      leadOff = 1;
    }

    int adcVal = analogRead(PIN_ANALOG_INPUT);

    // Protocolo serial estruturado: timestamp_us,adc,lead_off
    Serial.print(currentMicros);
    Serial.print(',');
    Serial.print(adcVal);
    Serial.print(',');
    Serial.println(leadOff);
  }
}
