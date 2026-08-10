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

> Le chemin raw de runtime.loadJar reste désactivé par défaut et exige un exact component explicitement sélectionné et signé comme l'hôte. R1 est clos: R1.1 7/7, R1.2 4/4 et matrice canonique du vrai provider 7/7. Le single-flight du Runtime de production utilise le cache sémantique persistant et borné après finalisation authentifiée de la clé. L'interruption de tout waiter, y compris le dernier, ne détache que cet appelant sans repli local; le producer peut terminer et remplir le cache. L'annulation coopérative du dernier waiter reste en R2 et le circuit de sûreté demeure prudent pendant la vie du processus.

******

### Guide d'installation et d'utilisation R1

******

Il s'agit du chemin R1 avec consentement explicite, désactivé par défaut, et non d'un compilateur de remplacement activé par la seule installation. L'acceptation R1 couvre désormais le vrai provider sur API 24/25/26/28/31/34/36, avec des émulateurs x86_64 et un appareil physique arm64. Cela clôt les portes R1 figées; cela n'active pas automatiquement le chemin, ne rend pas le plugin par défaut et n'élargit pas le protocole V1 borné.

#### Prérequis

Obtenez AutoJs6 et le plugin uniquement depuis une source de publication fiable et appariée. AutoJs6 doit être au build 5270 ou ultérieur, et les ensembles complets de certificats de signature actuels de l'hôte et du plugin doivent correspondre; les builds personnels doivent aussi conserver les identités de package et de service ci-dessous. Sauvegardez scripts et données importantes avant toute mise à niveau. Si Android signale une signature différente, ne contournez pas le contrôle en désinstallant l'hôte ou en effaçant ses données.

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### Installer et activer explicitement

Installez ou mettez d'abord à jour l'AutoJs6 compatible, puis installez l'APK du plugin. Dans AutoJs6, ouvrez Paramètres > À propos de l'application et du développeur, puis appuyez longuement sur l'icône pour ouvrir les options développeur. Ouvrez DEX compiler > Raw JAR compiler provider, sélectionnez l'exact component ci-dessous et confirmez. Installer le plugin ne suffit pas à activer la route, et AutoJs6 ne sélectionne jamais automatiquement un provider découvert.

#### Confirmer l'état

Revenez aux options développeur et vérifiez que le résumé indique explicitement que les JAR raw runtime.loadJar préfèrent l'exact component ci-dessous. S'il affiche Built-in D8/dx ou aucun candidat, vérifiez le build hôte, les deux noms de package, l'état activé du plugin et les signatures. Ce résumé prouve uniquement la sélection et l'éligibilité de découverte actuelles, pas qu'une compilation précise a été distante. La clôture de la matrice R1 ne supprime ni la revérification d'identité, ni le handshake, ni la validation, ni les règles de repli par requête.

#### Exemple AutoJs6

Placez un JAR lisible contenant des fichiers JVM `.class` dans `lib/example.jar` à côté du script, puis remplacez la classe et la méthode d'exemple par une API publique réellement présente dans ce JAR. Le script utilise le provider sélectionné via l'entrée existante `runtime.loadJar()`; le plugin n'ajoute aucun nouvel objet global JavaScript.

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

Cet exemple concerne uniquement les JAR raw. Les `.aar`, `.dex` précompilés, aides de compatibilité et `defineClass()` dynamique restent toujours sur les chemins intégrés de l'hôte. La validation ne sécurise pas un bytecode non fiable; ne chargez que des JAR de confiance.

#### Collecter les diagnostics

Pour signaler un problème, notez le build/version AutoJs6, la version du plugin, le résumé exact-component complet des options développeur, le modèle/API/ABI de l'appareil, la taille en octets et le SHA-256 du JAR d'entrée, l'heure, l'exception complète du script et les étapes de reproduction. Avec ADB, renseignez l'unique appareil autorisé dans `<serial>` pour chaque commande, capturez les journaux AndroidClassLoader/AndroidRuntime autour de l'échec et supprimez chemins privés, contenu du script et autres données sensibles avant partage.

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### Désactiver et revenir en urgence

Dans Options développeur > Raw JAR compiler provider, sélectionnez Built-in D8/dx et confirmez, puis arrêtez et redémarrez AutoJs6. La route expérimentale est coupée mais l'enregistrement du composant reste disponible pour une sélection ultérieure. En urgence, désactivez d'abord puis redémarrez l'hôte; inutile de désinstaller AutoJs6, d'effacer ses données ou de supprimer les scripts. Un circuit de sécurité ouvert reste volontairement ouvert jusqu'à la fin du processus AutoJs6.

#### Comprendre le fallback

Si la route est coupée, le provider indisponible ou incompatible, le binding ou le travail distant échoue, un délai expire, la sortie est invalide ou l'adoption d'un artefact vérifié échoue, un appel peut tenter au plus une fois le D8/dx intégré; un travail Binder déjà dispatché n'est pas relancé automatiquement. L'annulation ou l'interruption du thread se propage sans fallback local. AAR, loadDex et defineClass n'utilisent jamais ce plugin. Le succès final d'un script prouve donc seulement qu'un chemin autorisé a réussi, pas que le plugin a compilé le JAR.

#### Désinstaller et restaurer

Sélectionnez d'abord Built-in D8/dx, confirmez dans le résumé que l'expérience est désactivée, puis arrêtez AutoJs6 et désinstallez le plugin. La désinstallation supprime définitivement les données et espaces temporaires privés du plugin; l'hôte peut continuer avec son compilateur intégré. Pour restaurer, installez un plugin compatible et signé de manière identique, rouvrez les options développeur et sélectionnez de nouveau explicitement l'exact component; ne supposez pas que l'ancienne sélection se réactive seule.

#### Limites connues et frontière d'acceptation

V1 effectue uniquement la conversion bornée de JAR JVM raw vers DEX ZIP. Il ne fournit ni shrinking/obfuscation R8, ni classpath externe, ni bibliothèque desugared personnalisée, ni compilation réseau, ni sortie binaire déterministe. BUSY peut mener au fallback hôte et le travail CPU D8 peut continuer dans le processus isolé jusqu'au nettoyage après annulation. L'annulation coopérative après le départ du dernier waiter reste en R2; la promotion des performances, l'activation par défaut et la suppression des dépendances du compilateur hôte sont hors du R1 achevé.

******

### Feuille de route

******

R1 est clos: R1.1 production 7/7, R1.2 automatisation 4/4, R1.3 matrice réelle 7/7 et trois conditions de sortie cochées. Le production routing API 34 a réussi 8/8; host DEX 16 suites/149 tests, wire 4/24, fake-provider 5/25 et les 48 tests du plugin ont réussi, avec lint à 0 erreur. La campagne canonique f3c2b1af-be93-41e7-b541-f167f90e5cc1 a validé ses sept cellules avec le vrai provider: API 24/25 CLI, API 26/28/34/36 D8Command sur x86_64 et API 31 sur l'appareil QV arm64 multi-utilisateur. Son journal head est a5abaf62 et le SHA-256 du runner ca89ac16; les campagnes antérieures échouées ou arrêtées sont conservées. Le chemin reste désactivé par défaut, et l'annulation coopérative du dernier waiter ainsi que la récupération élargie restent décochées en R2.

- [Ouvrir le ROADMAP.md à cocher](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

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
