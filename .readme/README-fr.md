<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>Plugin de compilation DEX autonome. Compilation de JAR vérifiés en ZIP classes*.dex contigu avec D8</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### Langues

******

Le fichier README.md actuel prend en charge les langues suivantes:

- [简体中文 [zh-Hans]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hans.md)
- [繁體中文 (香港) [zh-Hant-HK]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-HK.md)
- [繁體中文 (台灣) [zh-Hant-TW]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-TW.md)
- [English [en]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-en.md)
- Français [fr] # actuel
- [Español [es]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-es.md)
- [日本語 [ja]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ja.md)
- [한국어 [ko]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ko.md)
- [Русский [ru]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ru.md)
- [العربية [ar]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ar.md)

******

### Introduction

******

DEX Compiler est un provider autonome pour la version 1 du protocole DEX Compiler d'AutoJs6. Il utilise D8 dans un espace privé de l'application pour compiler un JAR JVM strictement vérifié et renvoie un DEX ZIP canonique par un descripteur de sortie fourni par l'hôte.

******

### Fonctions

******

- Accepter un JAR en mode DEBUG ou RELEASE avec minApi de 24 à 36 et une sortie multi-dex.
- Vérifier la taille et SHA-256 déclarés, le framing ZIP, les noms des entries, le magic des classes, les doublons et les limites de décompression avant compilation.
- Compiler avec le runtime boot classpath de l'appareil et son empreinte sans accepter de classpath externe.
- Empaqueter uniquement `classes.dex`, `classes2.dex` et les DEX suivants sans rupture, puis indiquer la taille et SHA-256 réels du ZIP.
- Utiliser D8Command sur Android API 26 et ultérieur et le fallback CLI D8 sur API 24 et 25.

******

### Formats d'entrée et de sortie

******

La version 1 déclare uniquement le périmètre de compilation suivant:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.17
```

******

### Interface du plugin

******

L'hôte découvre et appelle le plugin avec les identités suivantes:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

Le plugin déclare D8 8.13.17, une entrée JAR, une sortie DEX ZIP, les modes DEBUG et RELEASE, minApi de 24 à 36 et multi-dex. Le modèle de runtime library est le boot classpath V1 de l'appareil.

La build hôte 5270 ou ultérieure est requise. Le plugin ne contient aucune bibliothèque native, donc un APK universal pur JVM couvre toutes les ABI.

******

### État de l'intégration hôte

******

> Le DEX adapter actuel de AutoJs6 reste une fonction experimental désactivée par défaut et ne se connecte pas à AndroidClassLoader. Installer uniquement ce plugin ne remplace pas le chemin JAR vers DEX par défaut. Une utilisation de bout en bout exige un futur adapter hôte ou son activation explicite avec la sélection de ce compiler provider.

******

### Sécurité

******

Le plugin ne demande aucune permission réseau ou de stockage. Le service est protégé par `org.autojs.permission.PLUGIN` et vérifie le paquet AutoJs6, le propriétaire de l'UID appelant et les signatures correspondantes. Les descripteurs sont dupliqués avant le travail asynchrone. Les fichiers temporaires restent dans le cache privé et sont supprimés après la fin du worker.

******

### Limites opérationnelles

******

- Le JAR compressé est limité à 64 MiB et 20000 entries, avec 256 MiB de données décompressées au total.
- Les classes sont limitées à 128 MiB au total et 8 MiB par classe. Les rapports de compression par entry et globaux sont bornés.
- Le DEX ZIP est limité à 16 MiB et 64 entries DEX indexées sans rupture. Une requête peut choisir un plafond inférieur.
- Une seule session de compilation est active dans le processus. Une requête occupée reçoit une erreur BUSY réessayable.
- Les diagnostics sont limités à 64 KiB. Le texte d'erreur et la file de callbacks ont leurs propres limites.

******

### Limites et réserves

******

- Cancel ou close bloque immédiatement la publication, ferme les descripteurs et interrompt le worker, mais le travail CPU de D8 ne peut pas être interrompu de façon fiable.
- Après annulation, le slot reste occupé jusqu'à la sortie réelle du worker D8 et la fin du nettoyage. Les nouvelles requêtes reçoivent BUSY entre-temps.
- Le plugin ne revendique aucun déterminisme et n'accepte ni classpath externe ni configuration desugared library personnalisée.
- L'hôte revalide toujours la sortie avec son DexIndexedZipValidator complet. Les contrôles du plugin ne remplacent pas cette validation.
- Le runtime boot classpath varie selon le système. La requête doit correspondre à l'empreinte annoncée par le provider.

******

### Historique des versions

******

# v1.0.0

###### 2026/08/08

* `Fonction` Provider DEX Compiler V1 avec ID et moteur `dex-compiler`, provider ID `autojs6-d8` et variante `d8`
* `Fonction` Compilation JAR vers DEX ZIP avec DEBUG, RELEASE, minApi de 24 à 36, multi-dex et empreinte du runtime boot classpath de l'appareil
* `Fonction` Limites pour la taille JAR, les entries, les données décompressées, les classes, les diagnostics et la sortie avec validation stricte du framing ZIP, des noms et du magic des classes
* `Fonction` Empaquetage de `classes*.dex` sans rupture avec taille et SHA-256 réels et revalidation par DexIndexedZipValidator dans l'hôte
* `Fonction` Une session active, contrôle de l'appelant AutoJs6 signé, espace privé, fallback CLI sur API 24 et 25 et annulation prudente
* `Fonction` Un APK universal pur JVM avec README, changelog, interface Android et instructions du plugin en 10 langues
* `Dépendance` Ajout de R8 8.13.17 pour la compilation D8

##### Autres versions

* [CHANGELOG-fr.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/assets/doc/CHANGELOG-fr.md)

******

### Build

******

```powershell
.\gradlew.bat :app:assembleDebug
```

Build de version:

```powershell
.\gradlew.bat :app:assembleRelease
```

Les paramètres viennent de `version.properties`. Le SDK minimal est 24, le SDK cible est 36, JDK 17 est le minimum et JDK 21 est recommandé.

L'ABI du protocole est fournie par les AAR locaux du dépôt dans `libs`:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

Le compilateur utilise D8 8.13.17 depuis Maven. Les AAR locaux fournissent seulement la frontière stable du protocole et le plugin obtenu est un APK universal sans bibliothèque native.

******

### Licence

******

Le code source du projet est sous MPL-2.0. R8 et les autres composants tiers conservent leurs licences respectives.

******

### Organisation des ressources

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

`.python/generate_markdown.py` produit les README et changelogs intégrés en 10 langues à partir des sources JSON. Les chaînes Android restent dans leurs propres dossiers de ressources.

******

### Liens

******

- Documentation AutoJs6: https://docs.autojs6.com
- Projet R8: https://r8.googlesource.com/r8
