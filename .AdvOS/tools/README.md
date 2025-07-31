# Système de compression AdvOS

## 📦 Compresseur et décompresseur pour AdvOS

Ce dossier contient le système de compression complet pour AdvOS, permettant de compresser et décompresser des fichiers et paquets.

## 🚀 Utilisation

### Commandes principales :

```bash
# Compresser un fichier
compress <input> <output> [format]

# Décompresser un fichier
decompress <input> <output>

# Analyser un fichier compressé
analyze <file>

# Compresser un paquet AdvOS
package <input> <output>

# Décompresser un paquet AdvOS
unpackage <input> <output>

# Benchmark des algorithmes
benchmark <file>

# Aide
help
```

## 📋 Formats supportés

- **`.advz`** - Format compressé AdvOS (par défaut)
- **`.advp`** - Format paquet AdvOS
- **`.zip`** - Format ZIP standard

## 🔧 Algorithmes de compression

### 1. LZW (Lempel-Ziv-Welch)
- **Avantages** : Bonne compression pour texte répétitif
- **Utilisation** : Par défaut pour les fichiers texte

### 2. RLE (Run-Length Encoding)
- **Avantages** : Excellent pour les données répétitives
- **Utilisation** : Images, données binaires

### 3. Huffman
- **Avantages** : Compression optimale basée sur la fréquence
- **Utilisation** : Fichiers avec distribution de caractères inégale

## 📊 Métadonnées

Chaque fichier compressé contient :
- Format et version
- Algorithme utilisé
- Taille originale et compressée
- Ratio de compression
- Date de compression

## 🎯 Exemples d'utilisation

```bash
# Compresser un fichier texte
compress mon_fichier.txt mon_fichier.advz

# Compresser un paquet AdvOS
package mon_paquet.advp mon_paquet.advz

# Analyser un fichier compressé
analyze fichier_compresse.advz

# Benchmark pour choisir le meilleur algorithme
benchmark gros_fichier.txt
```

## 📈 Performance

Le système choisit automatiquement le meilleur algorithme en fonction du contenu :
- **LZW** : Pour texte avec répétitions
- **RLE** : Pour données répétitives
- **Huffman** : Pour distribution de caractères optimale

## 🔒 Sécurité

- Vérification d'intégrité des fichiers compressés
- Détection automatique du format
- Gestion d'erreurs robuste

## 📝 Notes techniques

- Compatible avec le VFS AdvOS
- Support complet des paquets `.advp`
- Interface utilisateur intuitive
- Documentation complète 