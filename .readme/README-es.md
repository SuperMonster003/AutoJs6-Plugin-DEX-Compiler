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

> El DEX adapter actual de AutoJs6 sigue siendo una función experimental desactivada por defecto y no está conectado a AndroidClassLoader. Instalar solo este plugin no reemplaza la ruta JAR a DEX predeterminada. El uso de extremo a extremo requiere un futuro adapter del host o su activación explícita y la selección de este compiler provider.

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
