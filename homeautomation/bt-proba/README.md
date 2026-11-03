# BT próba

Osobna aplikacja pomiarowa na T-Rex 3 do kroku 1 z `SmartTermostatOLED/docs/ARCHITEKTURA.md`, pkt 4.9. Współpracuje
z firmware `SmartTermostatOLED/nodes/btnode-proba` na S3-Zero i niczym w domu nie steruje.

```
npm install
npm test
zeus preview
```

- **Pomiar**: telefon przed połączeniem, skan, łączenie, profil, pierwsze echo, 20 ramek, ramka 100 B (czy zadziałało
  większe MTU), telefon w trakcie połączenia z ESP32.
- **Seria**: 20 połączeń; pierwsze ze skanem, kolejne po znanym adresie. Kryterium: średnio do 1,5 s.
- **Skan ESP**: `tak` włącza pasywne skanowanie na węźle na czas pomiaru.

Czasy mają postać min/średnia/max w ms. Bateria nie jest mierzona: porównaj jej spadek ręcznie.
