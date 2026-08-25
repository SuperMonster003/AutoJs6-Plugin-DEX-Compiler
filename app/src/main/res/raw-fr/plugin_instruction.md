# Compilateur DEX AutoJs6

Ce plug-in compile une archive JAR normalisée avec D8 8.13.22 et renvoie un ZIP borné contenant des entrées `classes*.dex` contiguës.

Le plug-in exige la version 5270 ou ultérieure de l'hôte et Android API 24 ou ultérieure.

Limites de sécurité et de fonctionnement:

- Seul l'hôte AutoJs6 signé avec la même clé peut lier le service de compilation.
- La taille, le SHA-256, la structure ZIP, les chemins, les taux de compression et les fichiers class sont vérifiés avant la compilation.
- La sortie est limitée à 16 MiB et à 64 entrées DEX indexées contiguës.
- L'annulation arrête la publication, mais D8 peut continuer jusqu'au retour de la compilation en cours.
- L'hôte valide indépendamment le ZIP DEX avant sa mise en cache ou son chargement.
- Le plug-in ne demande aucune autorisation de stockage ou de réseau.
