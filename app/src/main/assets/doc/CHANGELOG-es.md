******

### Historial de versiones

******

# v1.0.0

###### 2026/08/08

* `Función` Provider DEX Compiler V1 con ID y motor `dex-compiler`, provider ID `autojs6-d8` y variante `d8`
* `Función` Compilación de JAR a DEX ZIP con DEBUG, RELEASE, minApi de 24 a 36, multi-dex y huella del runtime boot classpath del dispositivo
* `Función` Límites para tamaño JAR, entries, datos descomprimidos, clases, diagnósticos y salida con validación estricta de framing ZIP, nombres y magic de clases
* `Función` Empaquetado contiguo de `classes*.dex` con tamaño y SHA-256 reales y revalidación del host mediante DexIndexedZipValidator
* `Función` Una sesión activa, control del llamador AutoJs6 con la misma firma, espacio privado, fallback CLI en API 24 y 25 y cancelación conservadora
* `Función` Un APK universal JVM puro con README, changelog, interfaz Android e instrucciones del plugin en 10 idiomas
* `Dependencia` Se añadió R8 8.13.17 para la compilación D8
