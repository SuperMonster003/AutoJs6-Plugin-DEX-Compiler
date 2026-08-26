******

### Historique des versions

******

# v1.1.0

###### 2026/08/27

* `Conseil` `runtime.loadJarWithClasspath()` exige un build AutoJs6 associé 5274 ou ultérieur; `runtime.loadJar()` reste compatible avec le build 5270 ou ultérieur
* `Fonction` Ajoute le classpath ordonné de compilation V1.1: un JAR de programme peut référencer des JAR d'API externes, tandis que les entrées du classpath servent uniquement à la compilation et ne sont ni intégrées au DEX ni chargées automatiquement
* `Correction` Accepte les commentaires d'archive ZIP/JAR standard et bornés lorsque la longueur déclarée se termine exactement à la fin du fichier, tout en rejetant les enregistrements EOCD ambigus, les longueurs incohérentes et les données finales
* `Correction` Préserve le moteur D8 embarqué et ses fournisseurs de services dans les builds Release minifiés afin que les APK de production puissent compiler les entrées JAR
* `Amélioration` Fournit des diagnostics D8 info/warning/error bornés et respectueux de la confidentialité, avec les métadonnées disponibles de source, d'archive entry et de position, afin de faciliter l'analyse des échecs de compilation du plugin
* `Amélioration` Limite la compilation parallèle interne de D8 à deux threads de travail afin de réduire le pic mémoire des grands JAR compilés à froid, sans modifier la sortie ni la sémantique du cache
* `Dépendance` Met à niveau la bibliothèque Google R8 intégrée vers la version 8.13.22 (qui fournit le compilateur D8)

# v1.0.0

###### 2026/08/08

* `Conseil` Première version stable. Inactive par défaut après installation ; elle doit être activée manuellement dans les options développeur d'AutoJs6, voir la section « Installation et utilisation » du README
* `Fonction` Agit comme plugin de compilation DEX externe pour AutoJs6 : quand un script charge un JAR via `runtime.loadJar()`, ce plugin peut effectuer la compilation JAR vers DEX à la place du compilateur intégré
* `Fonction` La compilation s'exécute dans un bac à sable privé au sein du processus du plugin, isolé d'AutoJs6 ; si le plugin échoue ou est indisponible, AutoJs6 revient au compilateur intégré au plus une fois
* `Fonction` Valide strictement la taille, le SHA-256, la structure ZIP, les noms d'entrées et le contenu des classes du JAR avant compilation, en rejetant les entrées malformées, trop volumineuses ou falsifiées
* `Fonction` Prend en charge les modes de compilation DEBUG et RELEASE, la sortie multi-dex et minApi 24 à 36 ; la sortie est un ZIP `classes*.dex` numéroté consécutivement, rapporté avec sa taille réelle et son SHA-256
* `Fonction` Compatible avec les appareils sous Android 7.0 (API 24) et supérieur ; l'API 26+ utilise D8Command tandis que les API 24/25 utilisent automatiquement un chemin de compatibilité D8 CLI
* `Fonction` Communique uniquement avec un AutoJs6 de signature identique (protégé par la permission `org.autojs.permission.PLUGIN`) et ne demande aucune permission réseau ni stockage
* `Fonction` Implémentation pure JVM avec un unique APK universel couvrant toutes les architectures ; livré avec interface, README et instructions intégrées en 10 langues
* `Dépendance` Embarque la bibliothèque Google R8 8.13.17 (fournissant le compilateur D8)
