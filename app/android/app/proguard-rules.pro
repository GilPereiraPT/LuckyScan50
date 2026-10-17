# The plugin references optional language-specific ML Kit implementations.
# LuckyScan50 initializes TextRecognitionScript.latin only.
# Suppress absent optional recognizer APIs without bundling their models.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
