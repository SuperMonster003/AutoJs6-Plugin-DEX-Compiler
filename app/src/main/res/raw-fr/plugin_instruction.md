# Compilateur DEX AutoJs6

Ce plug-in permet à AutoJs6 de compiler les JAR avec D8 8.13.22 dans un processus séparé. Il prend en charge `runtime.loadJar()` et le classpath de compilation ordonné utilisé par `runtime.loadJarWithClasspath()`.

## Avant l'activation

- Le plug-in est désactivé par défaut. L'installation de son APK ne modifie pas le comportement d'AutoJs6.
- AutoJs6 build 5270 ou ultérieur et Android 7.0 (API 24) ou ultérieur sont requis. Le point d'entrée classpath exige un build hôte appairé plus récent.
- AutoJs6 et le plug-in doivent avoir des signatures identiques. Un plug-in dont la signature diffère ne peut pas être sélectionné.

## Activer le plug-in

1. Installez ou mettez à niveau l'hôte AutoJs6 compatible, puis installez l'APK de ce plug-in.
2. Dans AutoJs6, ouvrez Paramètres > À propos de l'application et du développeur, puis appuyez longuement sur l'icône de l'application pour accéder aux options pour les développeurs.
3. Ouvrez DEX compiler > Raw JAR compiler provider.
4. Sélectionnez le composant de service de ce plug-in et confirmez.

Le résumé du provider indique que le plug-in est sélectionné; un chargement donné peut encore utiliser un résultat en cache ou le repli intégré.

## Utilisation et récupération

Appelez normalement `runtime.loadJar()` ou `runtime.loadJarWithClasspath()`. Le plug-in n'ajoute aucun global JavaScript et ne peut pas lire le chemin d'origine du script.

Si le plug-in est indisponible, occupé, arrive à expiration, échoue à compiler ou renvoie une sortie invalide, AutoJs6 réessaie la même requête avec son compilateur intégré au plus une fois. Une annulation volontaire ne déclenche aucun repli. Pour désactiver le plug-in, sélectionnez Built-in D8/dx sur la même page puis redémarrez AutoJs6; il est inutile de désinstaller l'hôte ou d'effacer ses données.

## Sécurité et limites

- Seul l'hôte AutoJs6 signé de façon identique peut lier le service de compilation.
- La taille, le SHA-256, la structure ZIP, les chemins, les taux de compression et les fichiers class sont vérifiés avant la compilation; AutoJs6 vérifie aussi indépendamment le ZIP DEX avant sa mise en cache ou son chargement.
- La sortie est limitée à 16 MiB et à 64 entrées `classes*.dex` contiguës.
- Le plug-in ne demande aucune autorisation de stockage ou de réseau. Il effectue uniquement la compilation D8, sans réduction ni obfuscation R8.

Pour signaler un problème, indiquez le build AutoJs6, la version du plug-in, l'API Android, l'ABI de l'appareil, les étapes de reproduction et l'erreur complète du script. Retirez des journaux les chemins privés et contenus sensibles avant de les partager.
