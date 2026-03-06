/*
 * blink.ino — Test sketch for Arduino Auto-Deploy System
 *
 * LED blinks on built-in LED (pin 13 on most boards).
 * If this uploads successfully, your CI/CD pipeline works!
 */

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(9600);
  Serial.println("Auto-Deploy OK — Blink running!");
}

void loop() {
  digitalWrite(LED_BUILTIN, HIGH);
  delay(1000);
  digitalWrite(LED_BUILTIN, LOW);
  delay(1000);
}
