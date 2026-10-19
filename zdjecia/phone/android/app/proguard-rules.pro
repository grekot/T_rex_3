# Wtyczka ML Kit odwołuje się do modeli pisma chińskiego/japońskiego/koreańskiego/dewanagari,
# których nie dołączamy (używamy tylko alfabetu łacińskiego) - R8 ma je pominąć.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
