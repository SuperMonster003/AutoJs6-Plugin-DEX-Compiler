<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>Plugin de compilación DEX independiente. Compila JAR validados en un ZIP classes*.dex contigu con D8</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### Idiomas

******

El README.md actual admite los siguientes idiomas:

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

DEX Compiler es un provider independiente para la versión 1 del protocolo DEX Compiler de AutoJs6. Usa D8 en un espacio privado de la aplicación para compilar un JAR JVM estrictamente validado y devuelve un DEX ZIP canónico mediante un descriptor de salida suministrado por el host.

******

### Funciones

******

- Aceptar un JAR en modo DEBUG o RELEASE con minApi de 24 a 36 y salida multi-dex.
- Verificar el tamaño y SHA-256 declarados, framing ZIP, nombres de entries, magic de clases, duplicados y límites de descompresión antes de compilar.
- Compilar con el runtime boot classpath del dispositivo y su huella sin aceptar un classpath externo.
- Empaquetar solo `classes.dex`, `classes2.dex` y los DEX posteriores sin huecos e informar el tamaño y SHA-256 reales del ZIP.
- Usar D8Command en Android API 26 o posterior y el fallback CLI de D8 en API 24 y 25.

******

### Formatos de entrada y salida

******

La versión 1 declara únicamente el siguiente alcance de compilación:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.17
```

******

### Interfaz del plugin

******

El host descubre y llama al plugin con las siguientes identidades:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

El plugin declara D8 8.13.17, entrada JAR, salida DEX ZIP, modos DEBUG y RELEASE, minApi de 24 a 36 y multi-dex. El modelo de runtime library es el boot classpath V1 del dispositivo.

Se requiere la build 5270 o posterior del host. El plugin no contiene bibliotecas nativas, por lo que un APK universal JVM puro admite todas las ABI.

******

### Estado de integración con el host

******

> La ruta raw de runtime.loadJar sigue desactivada por defecto y exige seleccionar explícitamente un exact component con la misma firma. El single-flight del Runtime de producción usa la caché semántica persistente y acotada después de finalizar la clave autenticada. Interrumpir cualquier waiter, incluido el último, solo separa a ese llamador sin fallback local; el producer puede terminar y llenar la caché. La cancelación cooperativa del último waiter queda para R2 y el circuito de seguridad se mantiene conservador durante la vida del proceso. Las pruebas del provider real en API 31 arm64 ya cubren committed remote dispatch, el ciclo de vida Binder y el corpus DexClassLoader definido, completando solo R1.2; R1.1 y la matriz multi-API/ABI siguen abiertos.

******

### Guía de instalación y uso de R1

******

> Esta es una ruta R1 de activación explícita y deshabilitada de forma predeterminada, no un compilador de reemplazo que se active al instalarlo. La matriz R1.3 de varias API/ABI sigue abierta; la evidencia canónica actual con el provider real solo cubre API 31 arm64. Por tanto, el rango de protocolo minApi 24 a 36 no equivale a aceptación en todos los dispositivos.

#### Requisitos previos

Obtén AutoJs6 y el plugin únicamente de una fuente de versiones emparejada y de confianza. AutoJs6 debe ser build 5270 o posterior y los conjuntos completos de certificados de firma actuales del host y del plugin deben coincidir; los builds propios también deben conservar las identidades fijas de paquete y servicio indicadas abajo. Haz una copia de seguridad de scripts y datos importantes antes de actualizar. Si Android informa de una firma distinta, no lo evites desinstalando el host ni borrando sus datos.

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### Instalar y habilitar explícitamente

Instala o actualiza primero el AutoJs6 compatible y luego instala el APK del plugin. En AutoJs6 abre Ajustes > Acerca de la aplicación y el desarrollador y mantén pulsado el icono para abrir Opciones de desarrollador. Abre DEX compiler > Raw JAR compiler provider, selecciona el exact component de abajo y confirma. Instalar el plugin por sí solo no habilita la ruta y AutoJs6 nunca selecciona automáticamente un provider descubierto.

#### Confirmar el estado

Vuelve a Opciones de desarrollador y confirma que el resumen dice explícitamente que los JAR raw runtime.loadJar prefieren el exact component de abajo. Si muestra Built-in D8/dx o no hay candidato, comprueba el build del host, ambos nombres de paquete, el estado habilitado del plugin y las firmas. El resumen solo prueba la selección actual y la elegibilidad para descubrimiento; no prueba que una compilación concreta fuera remota ni que R1.3 esté completo.

#### Ejemplo de AutoJs6

Coloca un JAR legible con archivos JVM `.class` en `lib/example.jar` junto al script y sustituye la clase y el método de ejemplo por una API pública que exista realmente en ese JAR. El script usa el provider seleccionado mediante la entrada existente `runtime.loadJar()`; el plugin no añade ningún global de JavaScript nuevo.

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

Este ejemplo solo cubre JAR raw. Los `.aar`, `.dex` precompilados, asistentes de compatibilidad y `defineClass()` dinámico permanecen siempre en las rutas integradas del host. La validación no vuelve seguro el bytecode no confiable; carga solo JAR de confianza.

#### Recopilar diagnósticos

Al informar de un problema, registra build/versión de AutoJs6, versión del plugin, resumen exact-component completo de Opciones de desarrollador, modelo/API/ABI del dispositivo, bytes y SHA-256 del JAR de entrada, hora del evento, excepción completa del script y pasos de reproducción. Si usas ADB, indica el único dispositivo autorizado en `<serial>` en cada comando, captura los logs AndroidClassLoader/AndroidRuntime alrededor del fallo y elimina rutas privadas, contenido del script y otros datos sensibles antes de compartir.

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### Deshabilitar y revertir en emergencia

En Opciones de desarrollador > Raw JAR compiler provider, selecciona Built-in D8/dx y confirma; después detén y reinicia AutoJs6. Esto apaga la ruta experimental, pero conserva el registro del componente para volver a seleccionarlo. En una emergencia, deshabilita primero y reinicia el host; no hace falta desinstalar AutoJs6, borrar sus datos ni eliminar scripts. Un circuito de seguridad abierto permanece abierto deliberadamente hasta que termina ese proceso de AutoJs6.

#### Entender el fallback

Si la ruta está apagada, el provider no está disponible o es incompatible, falla el binding o el trabajo remoto, vence el tiempo, la salida es inválida o falla la adopción de un artefacto verificado, una invocación puede intentar como máximo una vez el D8/dx integrado del host; el trabajo Binder ya dispatchado no se reintenta automáticamente. La cancelación del llamador o interrupción del hilo se propaga sin fallback local. AAR, loadDex y defineClass nunca usan este plugin. Por ello, que el script termine bien solo prueba que alguna ruta permitida funcionó, no que el plugin lo compiló.

#### Desinstalar y recuperar

Selecciona primero Built-in D8/dx, confirma que el resumen muestra el experimento apagado, detén AutoJs6 y desinstala el plugin. La desinstalación elimina permanentemente los datos y espacios temporales privados del plugin; el host puede continuar con su compilador integrado. Para recuperar, instala un plugin compatible con la misma firma, vuelve a Opciones de desarrollador y selecciona explícitamente otra vez el exact component; no supongas que la selección antigua se habilitará sola.

#### Límites conocidos y frontera de aceptación

V1 solo realiza conversión acotada de JAR JVM raw a DEX ZIP. No ofrece shrinking/obfuscation de R8, classpath externo, biblioteca desugared personalizada, compilación por red ni salida binaria determinista. BUSY puede llevar al fallback del host y el trabajo CPU de D8 puede continuar en el proceso aislado hasta la limpieza tras una cancelación. La evidencia R1.2 de API 31 arm64 no sustituye las puertas production fault/rollback de R1.1 ni la matriz R1.3 API 24/25/26/28/34/36 y x86_64/arm64; considera esta guía una vista previa controlada hasta que esas casillas estén marcadas.

******

### Hoja de ruta de desarrollo

******

R1.2 alcanza 4/4: pasaron 16 suites/149 tests DEX del host, la compilación Android-test Kotlin y el assemble de los APK host/test; en API 31 arm64 pasaron por separado dos métodos de concurrencia production, dos de ciclo de vida real y tres de corpus real. La sonda cuenta committed remote dispatch y no llamadas directas provider openSession; el gate multi-dex pesado separado generó 65 700 métodos y cargó clases desde los DEX primario y secundario. Los prefijos SHA-256 actuales de host/test/plugin son 181E38E8, 70FAE1E8 y 5B6AC53B con el mismo signer 31a681fc. R1.1 sigue 0/7 y R1.3 totalmente abierto. R2 solo inició un tramo de recuperación: el janitor process-once strict-canonical pasó 48/48 tests del plugin y 6/6 de workspace recovery, eliminó un UUID real obsoleto de force-stop antes de exponer el primer Binder y mantuvo vacío el workspace tras una carga D8 normal; los demás elementos R2 siguen sin marcar.

- [Abrir el ROADMAP.md verificable](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### Seguridad

******

El plugin no solicita permisos de red ni almacenamiento. El servicio está protegido por `org.autojs.permission.PLUGIN` y verifica el paquete AutoJs6, la propiedad del UID y las firmas coincidentes. Los descriptores se duplican antes del trabajo asíncrono. Los archivos temporales permanecen en la cache privada y se eliminan después de salir el worker.

******

### Límites operativos

******

- El JAR comprimido se limita a 64 MiB y 20000 entries, con 256 MiB de datos descomprimidos en total.
- Los datos de clase se limitan a 128 MiB en total y 8 MiB por clase. Las relaciones de compresión por entry y globales están limitadas.
- El DEX ZIP se limita a 16 MiB y 64 entries DEX con índices contiguos. Una solicitud puede elegir un máximo menor.
- Solo una sesión de compilación puede estar activa en el proceso. Las solicitudes ocupadas reciben un error BUSY reintentable.
- Los diagnósticos se limitan a 64 KiB. El texto de error y la cola de callbacks tienen límites propios.

******

### Limitaciones y advertencias

******

- Cancel o close impide inmediatamente publicar el resultado, cierra descriptores e interrumpe el worker, pero el trabajo CPU de D8 no se puede interrumpir de forma fiable.
- Tras cancelar, la sesión permanece ocupada hasta que el worker D8 sale y termina la limpieza. Las nuevas solicitudes reciben BUSY mientras tanto.
- El plugin no afirma determinismo y no acepta un classpath externo ni una configuración desugared library personalizada.
- El host vuelve a validar la salida con su DexIndexedZipValidator completo. Las comprobaciones del plugin no sustituyen la validación del host.
- El runtime boot classpath puede variar según el sistema. La solicitud debe coincidir con la huella informada por el provider.

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

Los parámetros proceden de `version.properties`. El SDK mínimo es 24, el SDK objetivo es 36, JDK 17 es el mínimo y se recomienda JDK 21.

La ABI del protocolo se suministra mediante AAR locales del repositorio en `libs`:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

El compilador usa D8 8.13.17 desde Maven. Los AAR locales solo aportan el límite estable del protocolo y el resultado es un APK universal sin bibliotecas nativas.

******

### Licencia

******

El código fuente del proyecto se distribuye bajo MPL-2.0. R8 y otros componentes de terceros mantienen sus licencias respectivas.

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

`.python/generate_markdown.py` genera README y changelogs integrados en 10 idiomas desde fuentes JSON. Las cadenas Android se mantienen en sus propios directorios de recursos.

******

### Enlaces

******

- Documentación de AutoJs6: https://docs.autojs6.com
- Proyecto R8: https://r8.googlesource.com/r8
