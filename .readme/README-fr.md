<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>Plugin autonome de compilation DEX pour AutoJs6. Compile les JAR de script en DEX avec un D8 récent, dans un processus isolé</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### Langues

******

Le fichier README.md est actuellement disponible dans les langues suivantes:

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

Les scripts AutoJs6 peuvent charger un JAR avec `runtime.loadJar()` et appeler les classes Java qu'il contient. Comme Android ne peut pas exécuter directement du bytecode JVM, ces JAR doivent d'abord être compilés en DEX ; par défaut, cette étape est assurée par le compilateur intégré à AutoJs6.

Ce plugin offre une alternative : c'est une application installée séparément qui effectue cette compilation avec une version plus récente du compilateur D8 de Google, dans son propre processus isolé. AutoJs6 confie le JAR au plugin, récupère le résultat DEX, puis le valide, le met en cache et le charge lui-même ; en cas de problème avec le plugin, AutoJs6 revient automatiquement à son compilateur intégré et les scripts continuent généralement de fonctionner.

Installez ce plugin si vous souhaitez un D8 plus récent que celui embarqué dans AutoJs6, si vous voulez que la compilation s'exécute dans un processus isolé d'AutoJs6, ou si vous voulez mettre à jour le compilateur indépendamment des mises à jour d'AutoJs6.

******

### Fonctionnement

******

Avec le plugin activé, un appel à `runtime.loadJar()` suit à peu près les étapes suivantes:

```text
1. script     calls runtime.loadJar() or runtime.loadJarWithClasspath()
2. AutoJs6    validates and freezes the input JAR, records its size and SHA-256
3. plugin     re-verifies the input, then compiles it with D8 in a private sandboxed process
4. plugin     returns a DEX ZIP (classes.dex, classes2.dex, ...)
5. AutoJs6    independently re-validates the result, caches it, and loads the classes
*  fallback   if anything fails, AutoJs6 retries once with its built-in compiler
```

Le plugin n'est responsable que des étapes 3 et 4, c'est-à-dire de la compilation elle-même ; le gel de l'entrée, la validation du résultat, la mise en cache et le chargement final des classes restent toujours du ressort d'AutoJs6. Les deux applications n'échangent que des descripteurs de fichiers via Binder : le plugin ne lit jamais votre répertoire de scripts et ne connaît pas les chemins d'origine. Les résultats sont mis en cache selon le contenu d'entrée et les paramètres de compilation ; recharger le même JAR touche donc le cache sans recompilation.

******

### Fonctionnalités

******

- La compilation est effectuée par D8 8.13.22 ; le plugin peut mettre à jour son compilateur indépendamment d'AutoJs6.
- La compilation s'exécute dans le processus et l'espace de travail privés du plugin : un plantage ou un échec n'affecte jamais le processus principal d'AutoJs6.
- Double validation : le plugin vérifie la taille, le SHA-256, la structure ZIP et le contenu des classes du JAR avant compilation ; AutoJs6 revalide ensuite indépendamment la sortie DEX.
- Prend en charge les modes de compilation DEBUG et RELEASE, la sortie multi-dex, et les paramètres minApi 24 à 36.
- Prend en charge tous les appareils sous Android 7.0 (API 24) ou supérieur ; l'API 26+ utilise D8Command, les API 24/25 basculent automatiquement vers un chemin de compatibilité D8 CLI.
- Le protocole V1.1 prend en charge un classpath de compilation ordonné (`runtime.loadJarWithClasspath()`) pour compiler des JAR référençant des API externes.
- En cas d'échec, AutoJs6 revient au compilateur intégré au plus une fois : les scripts ne restent jamais bloqués sur le plugin.

******

### Installation et utilisation

******

Activer le plugin se fait en trois étapes : installer un AutoJs6 compatible, installer l'APK du plugin, puis sélectionner manuellement le plugin dans les options développeur d'AutoJs6. Deux choses à savoir d'emblée :

- Le plugin est inactif par défaut. La simple installation ne change rien dans AutoJs6 ; il faut l'activer manuellement comme décrit ci-dessous.
- L'opération est réversible à tout moment. Revenir à Built-in D8/dx dans les options développeur restaure le comportement d'origine sans rien désinstaller.

#### Prérequis

- AutoJs6 build 5270 ou supérieur (pour `runtime.loadJar()`) ; `runtime.loadJarWithClasspath()` exige un build hôte apparié plus récent (le build 5274 a servi à la vérification).
- L'hôte et le plugin doivent provenir de la même source de confiance et porter des signatures identiques. En cas de signatures différentes, le plugin ne peut pas être sélectionné ; utilisez des paquets publiés par paire ou compilez les deux vous-même, et ne contournez jamais le problème en désinstallant l'hôte ou en effaçant ses données.
- Si vous compilez vous-même, conservez tels quels les noms de paquets et le composant de service ci-dessous.
- Sauvegardez vos scripts et données importantes avant toute mise à niveau.

Les identifiants concernés sont :

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### Installer et activer

1. Installez ou mettez à niveau vers un AutoJs6 compatible.
2. Installez l'APK de ce plugin.
3. Ouvrez AutoJs6, allez dans Paramètres > À propos de l'application et du développeur, puis effectuez un appui long sur l'icône de l'application pour entrer dans les options développeur.
4. Allez dans DEX compiler > Raw JAR compiler provider.
5. Sélectionnez le composant de service de ce plugin (l'exact component indiqué ci-dessus) et confirmez.

Pour insister : installer le plugin ne l'active pas, et AutoJs6 ne sélectionne jamais automatiquement un provider découvert ; les étapes 3 à 5 sont indispensables.

#### Confirmer l'activation

Revenez à la page des options développeur. Quand le résumé indique que le composant de service de ce plugin est sélectionné, le plugin est actif : la compilation de `runtime.loadJar()` et `runtime.loadJarWithClasspath()` est désormais confiée en priorité au plugin.

Si le plugin n'apparaît pas dans la liste, ou si le résumé affiche toujours Built-in D8/dx, vérifiez dans l'ordre : le build AutoJs6 est au moins 5270 ; les noms de paquets de l'hôte et du plugin correspondent à ceux ci-dessus ; l'application du plugin n'est pas désactivée par le système ; les deux signatures sont identiques.

Remarque : le résumé indique « qui est actuellement sélectionné », pas « qui a réellement effectué une compilation donnée » ; une compilation individuelle peut encore contourner le plugin à cause d'un cache atteint ou d'un fallback (voir ci-dessous).

#### Exemple de script

Placez un JAR contenant des fichiers `.class` JVM dans `lib/example.jar` de votre répertoire de scripts, puis appelez `runtime.loadJar()` comme d'habitude ; le plugin n'ajoute aucun objet global JavaScript, et les scripts s'écrivent exactement comme avec le compilateur intégré. Remplacez le nom de classe et la méthode de l'exemple par une API publique existant réellement dans votre JAR.

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

Si le JAR référence à la compilation des classes présentes dans l'environnement d'exécution mais absentes du JAR lui-même (par exemple des stubs d'API), utilisez le point d'entrée explicite avec classpath de compilation :

```javascript
runtime.loadJarWithClasspath(
    files.path("./lib/program.jar"),
    files.path("./lib/compile-api-stubs.jar"),
);
```

Trois points à connaître sur le classpath :

- Les JAR du classpath ne servent qu'à résoudre les références à la compilation ; ils ne sont ni intégrés à la sortie ni chargés automatiquement.
- Si le programme utilise réellement ces classes à l'exécution, elles doivent déjà exister dans la chaîne parente du class loader final (classes système Android ou classes fournies par AutoJs6). Charger d'abord un JAR de dépendance avec `runtime.loadJar()` ne suffit pas : cela ne crée qu'un loader frère.
- L'ordre déclaré du classpath compte et fait partie de l'identité de cache ; ce point d'entrée exige au moins un JAR de classpath.

Par ailleurs, les fichiers `.aar`, les `.dex` précompilés et les points d'entrée dynamiques comme `defineClass()` passent toujours par le chemin intégré d'AutoJs6 et ne concernent jamais ce plugin. Enfin, rappelez-vous que la compilation n'est pas un audit de sécurité : ne chargez que des JAR de confiance.

#### Que se passe-t-il en cas d'échec

Même avec le plugin activé, AutoJs6 fait toujours passer « le script doit continuer à tourner » en premier :

- `runtime.loadJar()` : si le plugin est indisponible, si la compilation échoue, expire, ou si la sortie échoue à la validation, AutoJs6 recompile automatiquement le même JAR avec le D8/dx intégré, au plus une fois par requête.
- `runtime.loadJarWithClasspath()` : le fallback est également limité à une fois et doit confier au D8 local exactement le même programme et le même classpath ; le classpath n'est jamais abandonné ni dégradé silencieusement.
- Une annulation volontaire (par exemple arrêter le script) n'est pas un échec : elle ne déclenche pas de fallback et met simplement fin au chargement.
- Quand le plugin renvoie BUSY (une seule session de compilation à la fois), AutoJs6 applique les règles ci-dessus ; relancez simplement le script un peu plus tard.

Par conséquent, un script qui fonctionne ne prouve pas que sa compilation est passée par le plugin ; en cas de doute, suivez les étapes de diagnostic ci-dessous.

#### Diagnostic et signalement

Si vous suspectez un dysfonctionnement du plugin, revenez d'abord à Built-in D8/dx et comparez le comportement. Pour signaler un problème, joignez autant que possible les informations suivantes :

- Build/version d'AutoJs6, version du plugin, et le nom de composant complet affiché dans le résumé des options développeur.
- Modèle d'appareil, version d'Android (API) et architecture CPU (ABI).
- Le JAR déclencheur (ou sa taille en octets et son SHA-256), l'exception complète du script et les étapes de reproduction.

Si vous êtes à l'aise avec ADB, les commandes suivantes collectent les journaux pertinents (remplacez `<serial>` par le numéro de série de votre appareil ; supprimez les chemins privés et contenus sensibles avant tout partage) :

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### Désactiver, revenir en arrière et désinstaller

- Désactivation temporaire : dans les options développeur, sous Raw JAR compiler provider, sélectionnez Built-in D8/dx et confirmez, puis quittez complètement et redémarrez AutoJs6. Le composant choisi reste mémorisé, vous pourrez le réactiver à tout moment.
- En urgence : désactiver et redémarrer l'hôte comme ci-dessus suffit ; inutile de désinstaller AutoJs6, d'effacer ses données ou de supprimer des scripts.
- Désinstaller le plugin : revenez d'abord à Built-in D8/dx, puis arrêtez AutoJs6 et désinstallez l'APK du plugin. La désinstallation supprime toutes les données et fichiers temporaires du plugin ; AutoJs6 continue avec son compilateur intégré.
- Après réinstallation, le plugin doit être réactivé manuellement ; l'ancienne sélection n'est pas restaurée automatiquement.

******

### FAQ

******

**Q : J'ai installé le plugin et rien n'a changé. Est-il cassé ?**

R : Non. Le plugin est désactivé par défaut et doit être activé manuellement dans les options développeur (voir ci-dessus) ; il n'affecte en outre que l'étape de compilation de `runtime.loadJar()` et `runtime.loadJarWithClasspath()`, rien d'autre.

**Q : Comment confirmer qu'une compilation a vraiment été effectuée par le plugin ?**

R : Le résumé des options développeur signifie seulement « le plugin est sélectionné ». Comme les échecs déclenchent un fallback automatique et que les résultats sont mis en cache, un script qui réussit n'implique pas que le plugin a compilé ; collectez les journaux comme décrit dans « Diagnostic et signalement ».

**Q : Ce plugin rendra-t-il mes scripts plus rapides ?**

R : Ses objectifs sont un compilateur plus récent, une validation d'entrée plus stricte et l'isolation des processus, pas la performance. La compilation prend à peu près le même temps qu'avec le compilateur intégré, et les résultats sont mis en cache par AutoJs6.

**Q : Le plugin prend-il en charge le shrinking/l'obfuscation R8 ? Le mode RELEASE est-il R8 ?**

R : Non et non. Ce plugin n'effectue que de la compilation D8 ; `RELEASE` sélectionne simplement le mode release de D8, sans shrinking, obfuscation ni mapping. Les capacités R8 relèvent d'un plugin provider séparé et indépendant.

**Q : Pourquoi l'hôte et le plugin doivent-ils avoir des signatures identiques ?**

R : C'est un contrôle de sécurité mutuel : il empêche d'autres applications de se faire passer pour AutoJs6 auprès du plugin, et empêche un plugin falsifié de se faire passer pour le service de compilation. En cas de différence, utilisez des paquets publiés par paire au lieu de désinstaller ou d'effacer des données.

**Q : Le plugin accède-t-il au réseau ou à mes fichiers ?**

R : Non. Le plugin n'a aucune permission réseau ni stockage ; il ne peut lire que le contenu transmis par AutoJs6 via des descripteurs de fichiers, et ses fichiers temporaires restent entièrement dans son répertoire privé.

******

### Limites du périmètre

******

Pour éviter tout malentendu, les points suivants sont explicitement hors du périmètre de ce plugin:

- Pas de shrinking, d'optimisation ni d'obfuscation R8, et pas de fichiers de mapping ; `RELEASE` sélectionne uniquement le mode release de D8.
- Pas de téléchargement ni de résolution de dépendances (aucune intégration Maven/Gradle), pas de compilation via le réseau.
- Pas de prise en charge des fichiers `.aar`, des `.dex` précompilés ni du bytecode dynamique `defineClass()` ; ils empruntent toujours le chemin intégré d'AutoJs6.
- Le classpath V1.1 est réservé à la compilation : il n'embarque pas de dépendances d'exécution et ne crée pas de class loaders combinés.
- Aucune garantie de sortie déterministe au niveau des octets : la même entrée peut produire des DEX différents mais équivalents selon la version du compilateur.
- Aucun remplacement de la validation de sortie d'AutoJs6 : l'hôte revalide toujours le résultat DEX indépendamment.
- Ne devient jamais automatiquement le compilateur par défaut : l'activation est toujours une décision explicite de l'utilisateur.

******

### Référence technique

******

Les sections suivantes s'adressent aux développeurs et intégrateurs ayant besoin de limites précises ; les simples utilisateurs du plugin peuvent généralement les ignorer.

#### Entrée et sortie

Le protocole V1.0 reçoit un raw program JAR via un descripteur d'entrée ; V1.1 reçoit un program JAR plus au moins un JAR de classpath de compilation ordonné dans le même bundle d'entrée borné. Les deux produisent une sortie de même forme:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.22
```

#### Identifiants de découverte du plugin

L'hôte découvre et invoque le plugin via les identifiants suivants:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

Le plugin déclare D8 8.13.22, la plage de protocole V1.0 à V1.1, l'entrée JAR, la sortie DEX ZIP, les modes DEBUG et RELEASE, minApi 24 à 36 et le multi-dex ; le runtime library model est le boot classpath V1 de l'appareil.

Le build 5270 est l'exigence hôte minimale pour V1.0 ; `runtime.loadJarWithClasspath()` exige un build hôte apparié avec prise en charge V1.1 (le build 5274 a servi à la vérification représentative). Le plugin ne contient aucune bibliothèque native et couvre tous les ABI d'appareils avec un unique APK universel pur JVM.

#### Modèle de sécurité

Le plugin ne demande aucune permission réseau ni stockage. Le service de compilation est protégé par la permission `org.autojs.permission.PLUGIN`, et chaque appel vérifie le nom de paquet AutoJs6, l'UID appelant et les signatures des deux parties. Entrées et sorties transitent par descripteurs de fichiers et sont copiées avant traitement asynchrone ; les fichiers temporaires résident uniquement dans le cache privé du plugin et sont nettoyés à la fin de la compilation.

#### Limites de ressources

Pour se défendre contre les entrées malveillantes ou malformées, le plugin applique des limites strictes à chaque étape ; les requêtes qui les dépassent sont rejetées d'emblée:

- JAR d'entrée : au plus 64 MiB compressé, 20000 entrées, et 256 MiB de données décompressées au total.
- Classpath V1.1 : au plus 32 JAR, 64 MiB par JAR compressé, 128 MiB de classpath compressé au total, et 256 MiB pour l'ensemble du bundle d'entrée.
- Données de classes : au plus 128 MiB au total et 8 MiB par classe ; les ratios de compression par entrée et globaux sont également bornés.
- DEX ZIP de sortie : au plus 16 MiB avec au plus 64 entrées DEX numérotées consécutivement ; les requêtes peuvent déclarer des plafonds inférieurs.
- Concurrence : une seule session de compilation active par processus ; les requêtes supplémentaires reçoivent une erreur BUSY réessayable.
- Les diagnostics sont plafonnés à 64 KiB, avec des plafonds séparés pour le texte d'erreur et la file de rappels.

#### Mises en garde

- Annuler ou fermer bloque immédiatement la publication du résultat et interrompt le worker, mais le travail CPU interne de D8 ne peut pas être arrêté de façon fiable et peut se poursuivre dans le processus isolé jusqu'au retour de la compilation en cours.
- Après une annulation, le créneau de session reste occupé jusqu'à la sortie effective du worker et la fin du nettoyage ; les nouvelles requêtes reçoivent BUSY entre-temps.
- Le plugin ne revendique aucune sortie déterministe ; l'identité de cache inclut la version du compilateur et l'empreinte du runtime, un changement de version ne réutilise donc jamais d'anciens résultats.
- V1.1 n'accepte que le classpath de compilation gelé et empaqueté par l'hôte ; aucun chemin de fichier de l'appelant ni configuration desugared library personnalisée.
- Le boot classpath du runtime varie selon les systèmes ; les requêtes doivent correspondre à l'empreinte runtime rapportée par le provider.

******

### Feuille de route

******

Le développement avance par étapes, et R0 à R5 sont terminées dans le périmètre actuellement autorisé avec des preuves vérifiables. Le candidat à parallélisme borné de R5.2 reste `NOT_PROMOTED`, car les trois cellules corrigées de latence added P95 sur cache hit avec processus à froid dépassent 100 ms. R5.3 a figé v1.1.0 avec D8 8.13.22, validé des cellules classpath représentatives avec le provider réel sur API 24/x86, API 34/x86_64 et API 35/arm64, et n'a trouvé aucune différence de condensat de sortie parmi 54 cellules productrices, tout en conservant `determinismClaim=NOT_CLAIMED`. R5.4 est close par une décision explicite du propriétaire : la prerelease existante du provider R8 indépendant a été convertie en Release non-prerelease tandis que son dépôt reste Private ; la publication du dépôt, la publication d'AutoJs6 build 5276 apparié et l'enregistrement manuel dans l'index officiel n'ont pas été effectués et sont reportés ensemble à un futur Gate public R8 G9 indépendant. Il ne s'agit pas d'une publication publique et le plugin reste désactivé par défaut. Pour les définitions de fin et les preuves par élément, voir :

- [Ouvrir le ROADMAP.md à cocher](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### Historique des versions

******

# v1.1.0

###### 2026/09/13

* `Note` `runtime.loadJarWithClasspath()` exige un build AutoJs6 associé 5274 ou ultérieur; `runtime.loadJar()` reste compatible avec le build 5270 ou ultérieur
* `Fonctionnalité` Ajoute le classpath ordonné de compilation V1.1: un JAR de programme peut référencer des JAR d'API externes, tandis que les entrées du classpath servent uniquement à la compilation et ne sont ni intégrées au DEX ni chargées automatiquement
* `Correctif` Accepte les commentaires d'archive ZIP/JAR standard et bornés lorsque la longueur déclarée se termine exactement à la fin du fichier, tout en rejetant les enregistrements EOCD ambigus, les longueurs incohérentes et les données finales
* `Correctif` Préserve le moteur D8 embarqué et ses fournisseurs de services dans les builds Release minifiés afin que les APK de production puissent compiler les entrées JAR
* `Amélioration` Fournit des diagnostics D8 info/warning/error bornés et respectueux de la confidentialité, avec les métadonnées disponibles de source, d'archive entry et de position, afin de faciliter l'analyse des échecs de compilation du plugin
* `Amélioration` Limite la compilation parallèle interne de D8 à deux threads de travail afin de réduire le pic mémoire des grands JAR compilés à froid, sans modifier la sortie ni la sémantique du cache
* `Amélioration` La vérification de compilation rejette les dépendances natives involontaires et produit un rapport JSON
* `Amélioration` Ressources traduites cohérentes, activation explicite du plugin et validation des paquets de publication
* `Dépendance` Met à niveau la bibliothèque Google R8 intégrée vers la version 8.13.22 (qui fournit le compilateur D8)

# v1.0.0

###### 2026/08/08

* `Note` Première version stable. Inactive par défaut après installation ; elle doit être activée manuellement dans les options développeur d'AutoJs6, voir la section « Installation et utilisation » du README
* `Fonctionnalité` Agit comme plugin de compilation DEX externe pour AutoJs6 : quand un script charge un JAR via `runtime.loadJar()`, ce plugin peut effectuer la compilation JAR vers DEX à la place du compilateur intégré
* `Fonctionnalité` La compilation s'exécute dans un bac à sable privé au sein du processus du plugin, isolé d'AutoJs6 ; si le plugin échoue ou est indisponible, AutoJs6 revient au compilateur intégré au plus une fois
* `Fonctionnalité` Valide strictement la taille, le SHA-256, la structure ZIP, les noms d'entrées et le contenu des classes du JAR avant compilation, en rejetant les entrées malformées, trop volumineuses ou falsifiées
* `Fonctionnalité` Prend en charge les modes de compilation DEBUG et RELEASE, la sortie multi-dex et minApi 24 à 36 ; la sortie est un ZIP `classes*.dex` numéroté consécutivement, rapporté avec sa taille réelle et son SHA-256
* `Fonctionnalité` Compatible avec les appareils sous Android 7.0 (API 24) et supérieur ; l'API 26+ utilise D8Command tandis que les API 24/25 utilisent automatiquement un chemin de compatibilité D8 CLI
* `Fonctionnalité` Communique uniquement avec un AutoJs6 de signature identique (protégé par la permission `org.autojs.permission.PLUGIN`) et ne demande aucune permission réseau ni stockage
* `Fonctionnalité` Implémentation pure JVM avec un unique APK universel couvrant toutes les architectures ; livré avec interface, README et instructions intégrées en 10 langues
* `Dépendance` Embarque la bibliothèque Google R8 8.13.17 (fournissant le compilateur D8)

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

Les paramètres de build proviennent de `version.properties`. Le SDK minimal actuel est 24, le SDK cible 36, le JDK minimal 17 et le JDK 21 est recommandé.

L'ABI du protocole est fournie par des AAR locaux dans le répertoire `libs` du dépôt:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

Le compilateur est importé via Maven en tant que D8 8.13.22. Les AAR locaux ne fournissent que la frontière de protocole stable, et le produit du build est un APK universel sans bibliothèques natives.

******

### Licence

******

Le code source du projet est sous licence MPL-2.0. R8 et les autres composants tiers restent soumis à leurs licences respectives.

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

`.python/generate_markdown.py` génère le README et le changelog intégré pour les 10 langues à partir des sources JSON ; pour modifier la documentation, éditez les sources JSON plutôt que le Markdown généré. Les chaînes d'interface Android sont gérées dans leurs répertoires de ressources respectifs.

******

### Liens

******

- Documentation AutoJs6: https://docs.autojs6.com
- Projet R8: https://r8.googlesource.com/r8


[16 KB page alignment and build verification](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/docs/16kb.md)
