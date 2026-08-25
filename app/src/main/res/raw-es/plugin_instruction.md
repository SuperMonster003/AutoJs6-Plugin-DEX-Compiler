# Compilador DEX de AutoJs6

Este complemento compila un JAR normalizado con D8 8.13.22 y devuelve un ZIP acotado con entradas `classes*.dex` contiguas.

El complemento requiere la compilación 5270 o posterior del host y Android API 24 o posterior.

Límites de seguridad y operación:

- Solo el host AutoJs6 con la misma firma puede enlazar el servicio de compilación.
- Antes de compilar se verifican de nuevo el tamaño, SHA-256, estructura ZIP, rutas, relaciones de compresión y archivos class.
- La salida se limita a 16 MiB y 64 entradas DEX indexadas contiguas.
- La cancelación detiene la publicación, pero D8 puede continuar hasta que termine la compilación actual.
- El host valida de forma independiente el ZIP DEX antes de almacenarlo o cargarlo.
- El complemento no solicita permisos de almacenamiento ni de red.
