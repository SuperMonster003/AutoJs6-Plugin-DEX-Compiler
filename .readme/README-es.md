<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>Plugin independiente de compilación DEX para AutoJs6. Compila los JAR de script a DEX con un D8 actualizado, en un proceso aislado</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### Idiomas

******

El archivo README.md está disponible actualmente en los siguientes idiomas:

- [简体中文 [zh-Hans]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hans.md)
- [繁體中文 (香港) [zh-Hant-HK]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-HK.md)
- [繁體中文 (台灣) [zh-Hant-TW]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-TW.md)
- [English [en]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-en.md)
- [Français [fr]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-fr.md)
- Español [es] # actual
- [日本語 [ja]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ja.md)
- [한국어 [ko]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ko.md)
- [Русский [ru]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ru.md)
- [العربية [ar]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ar.md)

******

### Introducción

******

Los scripts de AutoJs6 pueden cargar un JAR con `runtime.loadJar()` y llamar a las clases Java que contiene. Como Android no puede ejecutar bytecode JVM directamente, esos JAR deben compilarse primero a DEX; de forma predeterminada, este paso lo realiza el compilador integrado de AutoJs6.

Este plugin ofrece una alternativa: es una aplicación instalada por separado que realiza esa compilación con una versión más reciente del compilador D8 de Google, dentro de su propio proceso aislado. AutoJs6 entrega el JAR al plugin, recupera el resultado DEX y luego lo valida, lo guarda en caché y lo carga por su cuenta; si algo falla en el plugin, AutoJs6 vuelve automáticamente a su compilador integrado, por lo que los scripts suelen seguir funcionando.

Instala este plugin si quieres un D8 más nuevo que el incluido en AutoJs6, si quieres que la compilación se ejecute en un proceso aislado de AutoJs6, o si quieres actualizar el compilador con independencia de las actualizaciones de AutoJs6.

******

### Cómo funciona

******

Con el plugin habilitado, una llamada a `runtime.loadJar()` pasa aproximadamente por los siguientes pasos:

```text
1. script     calls runtime.loadJar() or runtime.loadJarWithClasspath()
2. AutoJs6    validates and freezes the input JAR, records its size and SHA-256
3. plugin     re-verifies the input, then compiles it with D8 in a private sandboxed process
4. plugin     returns a DEX ZIP (classes.dex, classes2.dex, ...)
5. AutoJs6    independently re-validates the result, caches it, and loads the classes
*  fallback   if anything fails, AutoJs6 retries once with its built-in compiler
```

El plugin solo se encarga de los pasos 3 y 4, es decir, de la compilación en sí; congelar la entrada, validar el resultado, la caché y la carga final de clases siempre quedan dentro de AutoJs6. Las dos aplicaciones solo intercambian descriptores de archivo a través de Binder, así que el plugin nunca lee tu directorio de scripts ni conoce las rutas originales. Los resultados se guardan en caché según el contenido de entrada y los parámetros de compilación, por lo que volver a cargar el mismo JAR acierta en la caché sin recompilar.

******

### Funciones

******

- La compilación la realiza D8 8.13.22; el plugin puede actualizar su compilador con independencia de AutoJs6.
- La compilación se ejecuta en el proceso y el espacio de trabajo privados del plugin, de modo que un fallo o cierre inesperado nunca afecta al proceso principal de AutoJs6.
- Validación doble: el plugin comprueba el tamaño, el SHA-256, la estructura ZIP y el contenido de clases del JAR antes de compilar; AutoJs6 revalida después la salida DEX de forma independiente.
- Admite los modos de compilación DEBUG y RELEASE, salida multi-dex y parámetros minApi de 24 a 36.
- Admite todos los dispositivos con Android 7.0 (API 24) o superior; API 26+ usa D8Command, mientras que API 24/25 cambian automáticamente a una ruta de compatibilidad D8 CLI.
- El protocolo V1.1 admite un classpath de compilación ordenado (`runtime.loadJarWithClasspath()`) para compilar JAR que referencian API externas.
- Ante cualquier fallo, AutoJs6 recurre a su compilador integrado como máximo una vez, de modo que los scripts nunca se quedan bloqueados en el plugin.

******

### Instalación y uso

******

Habilitar el plugin lleva tres pasos: instalar un AutoJs6 compatible, instalar el APK de este plugin y, después, seleccionar manualmente el plugin en las opciones de desarrollador de AutoJs6. Dos cosas que conviene saber de antemano:

- El plugin está inactivo por defecto. Instalarlo sin más no cambia nada en AutoJs6; hay que habilitarlo manualmente como se describe abajo.
- Se puede revertir en cualquier momento. Volver a Built-in D8/dx en las opciones de desarrollador restaura el comportamiento original sin desinstalar nada.

#### Requisitos previos

- AutoJs6 build 5270 o superior (para `runtime.loadJar()`); `runtime.loadJarWithClasspath()` requiere un build del host emparejado más reciente (para la verificación se usó el build 5274).
- El host y el plugin deben proceder de la misma fuente de confianza y llevar firmas idénticas. Con firmas distintas el plugin no puede seleccionarse; usa paquetes publicados en pareja o compila ambos tú mismo, y nunca lo soluciones desinstalando el host o borrando sus datos.
- Si compilas por tu cuenta, conserva sin cambios los nombres de paquete y el componente de servicio indicados abajo.
- Haz copia de seguridad de tus scripts y datos importantes antes de actualizar.

Los identificadores relevantes son:

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### Instalar y habilitar

1. Instala o actualiza a un AutoJs6 compatible.
2. Instala el APK de este plugin.
3. Abre AutoJs6, ve a Ajustes > Acerca de la aplicación y el desarrollador, y mantén pulsado el icono de la aplicación para entrar en las opciones de desarrollador.
4. Entra en DEX compiler > Raw JAR compiler provider.
5. Selecciona el componente de servicio de este plugin (el exact component mostrado arriba) y confirma.

Para insistir: instalar el plugin por sí solo no lo habilita, y AutoJs6 nunca selecciona automáticamente un provider descubierto; los pasos 3 a 5 son obligatorios.

#### Confirmar que está activo

Vuelve a la página de opciones de desarrollador. Cuando el resumen muestre seleccionado el componente de servicio de este plugin, el plugin está activo: desde ese momento, la compilación de `runtime.loadJar()` y `runtime.loadJarWithClasspath()` se confía preferentemente al plugin.

Si el plugin no aparece en la lista, o el resumen sigue mostrando Built-in D8/dx, comprueba en orden: que el build de AutoJs6 sea al menos 5270; que los nombres de paquete del host y del plugin coincidan con los de arriba; que el sistema no haya deshabilitado la aplicación del plugin; que ambas firmas sean idénticas.

Nota: el resumen indica "quién está seleccionado actualmente", no "quién realizó realmente una compilación concreta"; una compilación individual aún puede omitir el plugin por un acierto de caché o un fallback (ver abajo).

#### Ejemplo de script

Coloca un JAR con archivos `.class` de JVM en `lib/example.jar` dentro de tu directorio de scripts y llama a `runtime.loadJar()` como siempre; el plugin no añade ningún objeto global de JavaScript y los scripts se escriben exactamente igual que con el compilador integrado. Sustituye el nombre de clase y el método del ejemplo por una API pública que exista realmente en tu JAR.

```javascript
"use strict";

const jar = files.path("./lib/example.jar");
if (!files.isFile(jar)) {
    throw new Error("Missing JAR: " + jar);
}

runtime.loadJar(jar);

// Replace this with a public class that actually exists in example.jar.
const Example = Packages.com.example.autojs6.DexPluginExample;
console.log("DEX compiler example: " + Example.answer());
```

Si el JAR referencia en compilación clases que existen en el entorno de ejecución pero no forman parte del propio JAR (por ejemplo stubs de API), usa el punto de entrada explícito con classpath de compilación:

```javascript
runtime.loadJarWithClasspath(
    files.path("./lib/program.jar"),
    files.path("./lib/compile-api-stubs.jar"),
);
```

Tres cosas que saber sobre el classpath:

- Los JAR del classpath solo sirven para resolver referencias en compilación; ni se empaquetan en la salida ni se cargan automáticamente.
- Si el programa usa realmente esas clases en tiempo de ejecución, deben existir ya en la cadena parent del class loader final (como clases del sistema Android o clases incluidas con AutoJs6). Cargar antes un JAR de dependencia con `runtime.loadJar()` no lo consigue: solo crea un loader hermano.
- El orden declarado del classpath importa y forma parte de la identidad de caché; este punto de entrada requiere al menos un JAR de classpath.

Por otra parte, los archivos `.aar`, los `.dex` precompilados y los puntos de entrada dinámicos como `defineClass()` siempre pasan por la ruta integrada de AutoJs6 y nunca involucran a este plugin. Por último, recuerda que compilar no es una auditoría de seguridad: carga solo JAR en los que confíes.

#### Qué ocurre cuando falla la compilación

Incluso con el plugin habilitado, AutoJs6 sigue anteponiendo que "el script debe seguir funcionando":

- `runtime.loadJar()`: si el plugin no está disponible, la compilación falla, expira, o la salida no supera la validación, AutoJs6 recompila automáticamente el mismo JAR con el D8/dx integrado, como máximo una vez por petición.
- `runtime.loadJarWithClasspath()`: el fallback también es como máximo una vez y debe entregar al D8 local exactamente el mismo programa y classpath; el classpath nunca se descarta ni se degrada en silencio.
- Una cancelación deliberada (por ejemplo detener el script) no es un fallo: no dispara ningún fallback y simplemente termina la carga.
- Cuando el plugin devuelve BUSY (solo una sesión de compilación a la vez), AutoJs6 aplica las reglas anteriores; basta con reintentar el script un momento después.

En consecuencia, que un script funcione no demuestra que su compilación pasara por el plugin; cuando necesites certeza, usa los pasos de diagnóstico de abajo.

#### Diagnóstico y reporte

Si sospechas que el plugin no funciona bien, vuelve primero a Built-in D8/dx y compara el comportamiento. Al reportar un problema, incluye en lo posible la siguiente información:

- Build/versión de AutoJs6, versión del plugin y el nombre de componente completo del resumen de las opciones de desarrollador.
- Modelo del dispositivo, versión de Android (API) y arquitectura de CPU (ABI).
- El JAR que provoca el problema (o su tamaño en bytes y su SHA-256), la excepción completa del script y los pasos de reproducción.

Si manejas ADB, los siguientes comandos recogen los registros relevantes (sustituye `<serial>` por el número de serie de tu dispositivo; elimina rutas privadas y contenido sensible antes de compartir):

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### Deshabilitar, revertir y desinstalar

- Deshabilitar temporalmente: en las opciones de desarrollador, bajo Raw JAR compiler provider, selecciona Built-in D8/dx y confirma; después cierra por completo y reinicia AutoJs6. El registro del componente elegido se conserva, así que podrás reactivarlo cuando quieras.
- En una emergencia: basta con deshabilitar y reiniciar el host como se acaba de describir; no hace falta desinstalar AutoJs6, borrar sus datos ni eliminar scripts.
- Desinstalar el plugin: vuelve primero a Built-in D8/dx, luego detén AutoJs6 y desinstala el APK del plugin. La desinstalación elimina todos los datos y archivos temporales propios del plugin; AutoJs6 sigue funcionando con su compilador integrado.
- Tras reinstalar, el plugin debe habilitarse manualmente de nuevo; la selección anterior no se restaura sola.

******

### Preguntas frecuentes

******

**P: Instalé el plugin y nada cambió. ¿Está roto?**

R: No. El plugin está deshabilitado por defecto y debe habilitarse manualmente en las opciones de desarrollador (ver arriba); además solo afecta al paso de compilación de `runtime.loadJar()` y `runtime.loadJarWithClasspath()`, a nada más de tus scripts.

**P: ¿Cómo confirmo que una compilación la hizo realmente el plugin?**

R: El resumen de las opciones de desarrollador solo significa "el plugin está seleccionado". Como los fallos recurren automáticamente al compilador integrado y los resultados se guardan en caché, que un script funcione no implica que el plugin lo compilara; recoge registros como se describe en "Diagnóstico y reporte".

**P: ¿Este plugin hará mis scripts más rápidos?**

R: Sus objetivos son un compilador más nuevo, una validación de entrada más estricta y el aislamiento de procesos, no el rendimiento. La compilación tarda aproximadamente lo mismo que con el compilador integrado, y AutoJs6 guarda en caché los resultados.

**P: ¿El plugin admite shrinking/ofuscación R8? ¿El modo RELEASE es R8?**

R: No y no. Este plugin solo realiza compilación D8; `RELEASE` únicamente selecciona el modo release de D8 y no implica shrinking, ofuscación ni mapping. Las capacidades de R8 pertenecen a un plugin provider separado e independiente.

**P: ¿Por qué el host y el plugin deben tener firmas idénticas?**

R: Es una comprobación de seguridad mutua: impide que otras aplicaciones se hagan pasar por AutoJs6 ante el plugin, y que un plugin manipulado se haga pasar por el servicio de compilación. Ante una discrepancia, cambia a paquetes publicados en pareja en lugar de desinstalar o borrar datos.

**P: ¿El plugin accede a la red o a mis archivos?**

R: No. El plugin no tiene permisos de red ni de almacenamiento; solo puede leer el contenido que AutoJs6 le entrega mediante descriptores de archivo, y sus archivos temporales viven por completo en su directorio privado.

******

### Límites del alcance

******

Para evitar malentendidos, lo siguiente queda explícitamente fuera del alcance de este plugin:

- Sin shrinking, optimización ni ofuscación R8, y sin archivos de mapping; `RELEASE` solo selecciona el modo release de D8.
- Sin descarga ni resolución de dependencias (sin integración Maven/Gradle) y sin compilación por red.
- Sin manejo de archivos `.aar`, `.dex` precompilados ni bytecode dinámico `defineClass()`; siempre siguen la ruta integrada de AutoJs6.
- El classpath V1.1 es solo de compilación: no empaqueta dependencias de ejecución ni crea class loaders combinados.
- Sin garantía de salida determinista a nivel de bytes: la misma entrada puede producir DEX distintos pero equivalentes entre versiones del compilador.
- No sustituye la validación de salida de AutoJs6: el host siempre revalida el resultado DEX de forma independiente.
- Nunca se convierte automáticamente en el compilador predeterminado: habilitarlo es siempre una decisión explícita del usuario.

******

### Referencia técnica

******

Las siguientes secciones van dirigidas a desarrolladores e integradores que necesitan límites precisos; quienes solo usan el plugin normalmente pueden omitirlas.

#### Entrada y salida

El protocolo V1.0 recibe un raw program JAR a través de un descriptor de entrada; V1.1 recibe un program JAR más al menos un JAR de classpath de compilación ordenado dentro del mismo bundle de entrada acotado. Ambos producen salida de la misma forma:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.22
```

#### Identificadores de descubrimiento del plugin

El host descubre e invoca el plugin mediante los siguientes identificadores:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

El plugin declara D8 8.13.22, rango de protocolo V1.0 a V1.1, entrada JAR, salida DEX ZIP, modos DEBUG y RELEASE, minApi 24 a 36 y multi-dex; el runtime library model es el boot classpath V1 del dispositivo.

El build 5270 es el requisito mínimo del host para V1.0; `runtime.loadJarWithClasspath()` requiere un build del host emparejado con soporte V1.1 (para la verificación representativa se usó el build 5274). El plugin no contiene bibliotecas nativas y cubre todos los ABI de dispositivo con un único APK universal de JVM pura.

#### Modelo de seguridad

El plugin no solicita permisos de red ni de almacenamiento. El servicio de compilación está protegido por el permiso `org.autojs.permission.PLUGIN`, y cada llamada verifica el nombre de paquete de AutoJs6, el UID llamante y las firmas de ambas partes. Entradas y salidas viajan como descriptores de archivo y se copian antes del procesamiento asíncrono; los archivos temporales residen solo en la caché privada del plugin y se limpian al terminar la compilación.

#### Límites de recursos

Para defenderse de entradas maliciosas o malformadas, el plugin impone límites estrictos en cada etapa; las peticiones que los superan se rechazan de inmediato:

- JAR de entrada: como máximo 64 MiB comprimido, 20000 entradas y 256 MiB de datos descomprimidos en total.
- Classpath V1.1: como máximo 32 JAR, 64 MiB por JAR comprimido, 128 MiB de classpath comprimido en total y 256 MiB para todo el bundle de entrada.
- Datos de clases: como máximo 128 MiB en total y 8 MiB por clase; las relaciones de compresión por entrada y globales también están acotadas.
- DEX ZIP de salida: como máximo 16 MiB con no más de 64 entradas DEX numeradas consecutivamente; las peticiones pueden declarar techos inferiores.
- Concurrencia: solo una sesión de compilación activa por proceso; las peticiones adicionales reciben un error BUSY reintentable.
- Los diagnósticos se limitan a 64 KiB, con topes separados para el texto de error y la cola de callbacks.

#### Advertencias

- Cancelar o cerrar bloquea de inmediato la publicación del resultado e interrumpe el worker, pero el trabajo interno de CPU de D8 no puede detenerse de forma fiable y puede continuar en el proceso aislado hasta que la compilación en curso retorne.
- Tras una cancelación, la ranura de sesión sigue ocupada hasta que el worker sale de verdad y termina la limpieza; mientras tanto, las nuevas peticiones reciben BUSY.
- El plugin no declara salida determinista; la identidad de caché incluye la versión del compilador y la huella del runtime, así que un cambio de versión nunca reutiliza resultados antiguos.
- V1.1 solo acepta el classpath de compilación congelado y empaquetado por el host; no acepta rutas de archivo del llamante ni configuraciones desugared library personalizadas.
- El boot classpath del runtime varía entre sistemas; las peticiones deben coincidir con la huella de runtime que reporta el provider.

******

### Hoja de ruta de desarrollo

******

El desarrollo avanza por etapas, y de R0 a R4 están completadas con evidencia revisable. R5 está en curso: se reescribieron las guías de usuario y las instrucciones integradas; los diagnósticos acotados y redactados, el resumen de la última ruta conservado en el proceso y los casos Android autorizados de fallo/recuperación están cerrados; y un probador independiente completó «instalar → habilitar → ejecutar el script de ejemplo» sin bloqueos. El benchmark R5.2 y la política numérica de promoción están completos, pero el candidato actual no fue promovido porque falló el umbral de PSS combinado P95 en frío para el corpus grande. Quedan pendientes la aceptación V1.1 ampliada en dispositivos y la promoción de la versión. Para las definiciones de completitud y la evidencia de cada punto, ver:

- [Abrir el ROADMAP.md verificable](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### Historial de versiones

******

# v1.0.0

###### 2026/08/08

* `Consejo` Primera versión estable. Inactiva por defecto tras la instalación; debe habilitarse manualmente en las opciones de desarrollador de AutoJs6, ver la sección "Instalación y uso" del README
* `Función` Actúa como plugin externo de compilación DEX para AutoJs6: cuando un script carga un JAR con `runtime.loadJar()`, este plugin puede realizar la compilación de JAR a DEX en lugar del compilador integrado
* `Función` La compilación se ejecuta en un sandbox privado dentro del propio proceso del plugin, aislado de AutoJs6; si el plugin falla o no está disponible, AutoJs6 recurre a su compilador integrado como máximo una vez
* `Función` Valida estrictamente el tamaño, el SHA-256, la estructura ZIP, los nombres de entrada y el contenido de clases del JAR antes de compilar, rechazando entradas malformadas, sobredimensionadas o manipuladas
* `Función` Admite los modos de compilación DEBUG y RELEASE, salida multi-dex y minApi de 24 a 36; la salida es un ZIP `classes*.dex` numerado consecutivamente, reportado con su tamaño real y su SHA-256
* `Función` Compatible con dispositivos con Android 7.0 (API 24) o superior; API 26+ usa D8Command mientras que API 24/25 usan automáticamente una ruta de compatibilidad D8 CLI
* `Función` Se comunica solo con un AutoJs6 de firma idéntica (protegido por el permiso `org.autojs.permission.PLUGIN`) y no solicita permisos de red ni de almacenamiento
* `Función` Implementación JVM pura con un único APK universal que cubre todas las arquitecturas; incluye interfaz, README e instrucciones integradas en 10 idiomas
* `Corrección` Acepta comentarios de archivo ZIP/JAR estándar y acotados cuando la longitud declarada termina exactamente en el límite del archivo, y sigue rechazando registros EOCD ambiguos, longitudes incoherentes y datos finales
* `Corrección` Conserva el motor D8 integrado y sus proveedores de servicio en las compilaciones Release minificadas para que los APK de producción puedan compilar entradas JAR
* `Mejora` Limita la compilación paralela interna de D8 a dos hilos de trabajo para reducir el pico de memoria al compilar en frío JAR grandes, sin cambiar la salida ni la semántica de caché
* `Dependencia` Incluye la biblioteca Google R8 8.13.17 (que proporciona el compilador D8)

##### Más versiones

* [CHANGELOG-es.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/assets/doc/CHANGELOG-es.md)

******

### Compilación

******

```powershell
.\gradlew.bat :app:assembleDebug
```

Compilación de versión:

```powershell
.\gradlew.bat :app:assembleRelease
```

Los parámetros de compilación provienen de `version.properties`. El SDK mínimo actual es 24, el SDK objetivo 36, el JDK mínimo 17 y se recomienda JDK 21.

La ABI del protocolo la proporcionan AAR locales en el directorio `libs` del repositorio:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

El compilador se incorpora vía Maven como D8 8.13.22. Los AAR locales solo aportan la frontera estable del protocolo, y el producto de la compilación es un APK universal sin bibliotecas nativas.

******

### Licencia

******

El código fuente del proyecto usa la licencia MPL-2.0. R8 y los demás componentes de terceros siguen sujetos a sus propias licencias.

******

### Estructura de recursos

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

`.python/generate_markdown.py` genera el README y el changelog integrado en la aplicación para los 10 idiomas a partir de las fuentes JSON; para cambiar la documentación, edita las fuentes JSON en lugar del Markdown generado. Las cadenas de la interfaz Android se gestionan en sus respectivos directorios de recursos.

******

### Enlaces

******

- Documentación de AutoJs6: https://docs.autojs6.com
- Proyecto R8: https://r8.googlesource.com/r8
