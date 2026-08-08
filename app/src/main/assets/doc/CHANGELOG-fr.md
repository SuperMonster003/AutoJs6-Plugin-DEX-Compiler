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
