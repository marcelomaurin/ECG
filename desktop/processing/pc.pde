import processing.serial.*;

Serial myPort;        // The serial port
int xPos = 1;         // horizontal position of the graph
float height_old = 0;
float height_new = 0;
float inByte = 512;
float rawAdc = 512;
int BPM = 0;
int beat_old = 0;
float[] beats = new float[20];  // Buffer curto para média móvel ágil
int beatIndex = 0;
int validBeats = 0;
float threshold = 620.0;  // Threshold do detector legado
boolean belowThreshold = true;
PFont font;
boolean leadsOff = false;

final int SERIAL_BAUD = 115200;

void setup () {
  // set the window size:
  size(1000, 400);        

  // List all the available serial ports
  println("Portas seriais disponiveis:");
  println(Serial.list());
  
  if (Serial.list().length > 0) {
    // Open serial port at 115200 baud
    myPort = new Serial(this, Serial.list()[0], SERIAL_BAUD);
    myPort.bufferUntil('\n');
  } else {
    println("Nenhuma porta serial encontrada!");
  }
  
  background(0xff);
  font = createFont("Arial", 14, true);
  textFont(font);
}

void draw () {
  // Map and draw the line for new data point
  float mappedY = map(rawAdc, 0, 1023, 0, height);
  height_new = height - mappedY; 

  if (leadsOff) {
    stroke(0, 0, 0xff); // Linha azul para Lead-Off
  } else {
    stroke(0xff, 0, 0); // Linha vermelha para sinal válido
  }

  line(xPos - 1, height_old, xPos, height_new);
  height_old = height_new;

  // at the edge of the screen, go back to the beginning:
  if (xPos >= width) {
    xPos = 0;
    background(0xff);
  } else {
    xPos++;
  }

  // Painel de informações e BPM
  fill(0xff);
  noStroke();
  rect(0, 0, 320, 30);
  fill(0x00);
  if (leadsOff) {
    fill(0, 0, 255);
    text("ELETRODO DESCONECTADO (LO)", 15, 20);
  } else {
    fill(0);
    text("BPM: " + BPM + "  |  ADC: " + int(rawAdc) + " @ 115200 baud", 15, 20);
  }
}

void serialEvent (Serial myPort) {
  String inString = myPort.readStringUntil('\n');

  if (inString != null) {
    inString = trim(inString);

    // Ignora comentários e cabeçalhos (#ECG,...)
    if (inString.startsWith("#") || inString.length() == 0) {
      return;
    }

    // Protocolo Estruturado v2: timestamp_us,adc,lead_off
    if (inString.indexOf(',') != -1) {
      String[] parts = split(inString, ',');
      if (parts.length >= 3) {
        rawAdc = float(parts[1]);
        leadsOff = (int(parts[2]) == 1);
      }
    } 
    // Compatibilidade com protocolo legado
    else if (inString.equals("!")) {
      leadsOff = true;
      rawAdc = 512;
    } else {
      leadsOff = false;
      rawAdc = float(inString);
    }

    // Detecção de batimento (quando eletrodo conectado)
    if (!leadsOff) {
      if (rawAdc > threshold && belowThreshold) {
        calculateBPM();
        belowThreshold = false;
      } else if (rawAdc < threshold) {
        belowThreshold = true;
      }
    }
  }
}

void calculateBPM () {
  int beat_new = millis();
  int diff = beat_new - beat_old;
  if (diff > 250 && diff < 2000) { // Fisiologicamente válido (30-240 bpm)
    float currentBPM = 60000.0 / diff;
    beats[beatIndex] = currentBPM;
    beatIndex = (beatIndex + 1) % beats.length;
    if (validBeats < beats.length) validBeats++;

    float total = 0.0;
    for (int i = 0; i < validBeats; i++) {
      total += beats[i];
    }
    BPM = int(total / validBeats);
    beat_old = beat_new;
  }
}
