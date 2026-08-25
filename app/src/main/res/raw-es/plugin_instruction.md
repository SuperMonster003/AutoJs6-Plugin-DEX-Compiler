# Compilador DEX de AutoJs6

Este complemento permite a AutoJs6 compilar archivos JAR con D8 8.13.22 en un proceso separado. Admite `runtime.loadJar()` y el classpath ordenado de tiempo de compilación que utiliza `runtime.loadJarWithClasspath()`.

## Antes de activarlo

- El complemento está desactivado de forma predeterminada. Instalar su APK no cambia el comportamiento de AutoJs6.
- Se requiere AutoJs6 build 5270 o posterior y Android 7.0 (API 24) o posterior. El punto de entrada de classpath requiere una compilación de host emparejada más reciente.
- AutoJs6 y el complemento deben tener firmas idénticas. No se puede seleccionar un complemento cuya firma no coincida.

## Activar el complemento

1. Instala o actualiza el host AutoJs6 compatible y después instala el APK de este complemento.
2. En AutoJs6, abre Ajustes > Acerca de la aplicación y el desarrollador y mantén pulsado el icono de la aplicación para entrar en las opciones de desarrollador.
3. Abre DEX compiler > Raw JAR compiler provider.
4. Selecciona el componente de servicio de este complemento y confirma.

El resumen del provider significa que el complemento está seleccionado; una carga concreta aún puede usar un resultado almacenado en caché o el mecanismo integrado de respaldo.

## Uso y recuperación

Llama a `runtime.loadJar()` o `runtime.loadJarWithClasspath()` de la forma habitual. El complemento no añade variables globales de JavaScript y no puede leer la ruta original del script.

Si el complemento no está disponible, está ocupado, agota el tiempo, no puede compilar o devuelve una salida no válida, AutoJs6 vuelve a intentar la misma solicitud con su compilador integrado como máximo una vez. Una cancelación deliberada no activa el respaldo. Para desactivar el complemento, selecciona Built-in D8/dx en la misma página y reinicia AutoJs6; no es necesario desinstalar el host ni borrar sus datos.

## Seguridad y límites

- Solo el host AutoJs6 con la misma firma puede enlazar el servicio de compilación.
- Antes de compilar se comprueban el tamaño, SHA-256, estructura ZIP, rutas, relaciones de compresión y archivos class; AutoJs6 también verifica de forma independiente el ZIP DEX antes de almacenarlo o cargarlo.
- La salida se limita a 16 MiB y 64 entradas `classes*.dex` contiguas.
- El complemento no solicita permisos de almacenamiento ni de red. Solo realiza compilación D8, no reducción ni ofuscación R8.

Al informar de un problema, incluye el build de AutoJs6, la versión del complemento, la API de Android, la ABI del dispositivo, los pasos de reproducción y el error completo del script. Elimina rutas privadas y contenido sensible de los registros antes de compartirlos.
