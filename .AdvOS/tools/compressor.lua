-- ========================================
-- Système de compression AdvOS
-- ========================================
-- Compresseur et décompresseur pour les paquets AdvOS
-- Supporte les formats .advp et .advz

local Compressor = {
    VERSION = "1.0.0",
    AUTHOR = "AdvOS Team",
    
    -- Configuration
    COMPRESSION_LEVEL = 6,  -- Niveau de compression (1-9)
    CHUNK_SIZE = 1024,      -- Taille des chunks pour la compression
    
    -- Formats supportés
    FORMATS = {
        ADVZ = "advz",  -- Format compressé AdvOS
        ADVP = "advp",  -- Format paquet AdvOS
        ZIP = "zip"     -- Format ZIP standard
    },
    
    -- Initialisation
    init = function()
        print("=== Système de compression AdvOS v" .. Compressor.VERSION .. " ===")
        print("Auteur: " .. Compressor.AUTHOR)
        print("Formats supportés: .advz, .advp, .zip")
        print()
    end,
    
    -- ========================================
    -- COMPRESSION LZW (Lempel-Ziv-Welch)
    -- ========================================
    
    -- Compresser avec LZW
    compressLZW = function(data)
        local dictionary = {}
        local result = {}
        local dictSize = 256
        
        -- Initialiser le dictionnaire avec les caractères ASCII
        for i = 0, 255 do
            dictionary[string.char(i)] = i
        end
        
        local w = ""
        for i = 1, #data do
            local c = string.sub(data, i, i)
            local wc = w .. c
            
            if dictionary[wc] then
                w = wc
            else
                table.insert(result, dictionary[w])
                dictionary[wc] = dictSize
                dictSize = dictSize + 1
                w = c
            end
        end
        
        if w ~= "" then
            table.insert(result, dictionary[w])
        end
        
        return result
    end,
    
    -- Décompresser avec LZW
    decompressLZW = function(compressed)
        local dictionary = {}
        local dictSize = 256
        
        -- Initialiser le dictionnaire
        for i = 0, 255 do
            dictionary[i] = string.char(i)
        end
        
        local result = ""
        local w = dictionary[compressed[1]]
        result = result .. w
        
        for i = 2, #compressed do
            local k = compressed[i]
            local entry
            
            if dictionary[k] then
                entry = dictionary[k]
            elseif k == dictSize then
                entry = w .. string.sub(w, 1, 1)
            else
                error("Données compressées corrompues")
            end
            
            result = result .. entry
            dictionary[dictSize] = w .. string.sub(entry, 1, 1)
            dictSize = dictSize + 1
            w = entry
        end
        
        return result
    end,
    
    -- ========================================
    -- COMPRESSION RLE (Run-Length Encoding)
    -- ========================================
    
    -- Compresser avec RLE
    compressRLE = function(data)
        local result = {}
        local count = 1
        local current = string.sub(data, 1, 1)
        
        for i = 2, #data do
            local char = string.sub(data, i, i)
            if char == current and count < 255 then
                count = count + 1
            else
                table.insert(result, string.char(count))
                table.insert(result, current)
                current = char
                count = 1
            end
        end
        
        table.insert(result, string.char(count))
        table.insert(result, current)
        
        return table.concat(result)
    end,
    
    -- Décompresser avec RLE
    decompressRLE = function(compressed)
        local result = ""
        
        for i = 1, #compressed, 2 do
            local count = string.byte(string.sub(compressed, i, i))
            local char = string.sub(compressed, i + 1, i + 1)
            result = result .. string.rep(char, count)
        end
        
        return result
    end,
    
    -- ========================================
    -- COMPRESSION HUFFMAN
    -- ========================================
    
    -- Créer l'arbre de Huffman
    createHuffmanTree = function(data)
        local freq = {}
        
        -- Compter les fréquences
        for i = 1, #data do
            local char = string.sub(data, i, i)
            freq[char] = (freq[char] or 0) + 1
        end
        
        -- Créer les nœuds initiaux
        local nodes = {}
        for char, count in pairs(freq) do
            table.insert(nodes, {char = char, freq = count})
        end
        
        -- Construire l'arbre
        while #nodes > 1 do
            table.sort(nodes, function(a, b) return a.freq < b.freq end)
            
            local left = table.remove(nodes, 1)
            local right = table.remove(nodes, 1)
            
            table.insert(nodes, {
                freq = left.freq + right.freq,
                left = left,
                right = right
            })
        end
        
        return nodes[1]
    end,
    
    -- Générer les codes Huffman
    generateHuffmanCodes = function(node, code, codes)
        if node.char then
            codes[node.char] = code
        else
            generateHuffmanCodes(node.left, code .. "0", codes)
            generateHuffmanCodes(node.right, code .. "1", codes)
        end
    end,
    
    -- Compresser avec Huffman
    compressHuffman = function(data)
        local tree = Compressor.createHuffmanTree(data)
        local codes = {}
        Compressor.generateHuffmanCodes(tree, "", codes)
        
        -- Encoder les données
        local encoded = ""
        for i = 1, #data do
            local char = string.sub(data, i, i)
            encoded = encoded .. codes[char]
        end
        
        -- Créer le header avec l'arbre
        local header = textutils.serialize({tree = tree, codes = codes})
        
        return {
            header = header,
            data = encoded
        }
    end,
    
    -- Décompresser avec Huffman
    decompressHuffman = function(compressed)
        local header = textutils.unserialize(compressed.header)
        local tree = header.tree
        local codes = header.codes
        
        -- Créer la table de décodage inverse
        local decodeTable = {}
        for char, code in pairs(codes) do
            decodeTable[code] = char
        end
        
        -- Décoder les données
        local result = ""
        local current = ""
        
        for i = 1, #compressed.data do
            current = current .. string.sub(compressed.data, i, i)
            if decodeTable[current] then
                result = result .. decodeTable[current]
                current = ""
            end
        end
        
        return result
    end,
    
    -- ========================================
    -- COMPRESSION AVANCÉE (Multi-algorithme)
    -- ========================================
    
    -- Compresser avec plusieurs algorithmes
    compressAdvanced = function(data, format)
        local compressed = {}
        
        -- Métadonnées
        compressed.format = format or "advz"
        compressed.originalSize = #data
        compressed.compressedAt = os.epoch("local")
        compressed.version = Compressor.VERSION
        
        -- Choisir le meilleur algorithme
        local lzwData = Compressor.compressLZW(data)
        local rleData = Compressor.compressRLE(data)
        local huffmanData = Compressor.compressHuffman(data)
        
        -- Comparer les tailles
        local lzwSize = #textutils.serialize(lzwData)
        local rleSize = #rleData
        local huffmanSize = #textutils.serialize(huffmanData.header) + #huffmanData.data
        
        -- Choisir le plus petit
        if lzwSize <= rleSize and lzwSize <= huffmanSize then
            compressed.algorithm = "lzw"
            compressed.data = lzwData
        elseif rleSize <= huffmanSize then
            compressed.algorithm = "rle"
            compressed.data = rleData
        else
            compressed.algorithm = "huffman"
            compressed.data = huffmanData
        end
        
        compressed.compressedSize = #textutils.serialize(compressed)
        compressed.ratio = math.floor((1 - compressed.compressedSize / compressed.originalSize) * 100)
        
        return compressed
    end,
    
    -- Décompresser avec détection automatique
    decompressAdvanced = function(compressed)
        if compressed.algorithm == "lzw" then
            return Compressor.decompressLZW(compressed.data)
        elseif compressed.algorithm == "rle" then
            return Compressor.decompressRLE(compressed.data)
        elseif compressed.algorithm == "huffman" then
            return Compressor.decompressHuffman(compressed.data)
        else
            error("Algorithme de compression inconnu: " .. (compressed.algorithm or "nil"))
        end
    end,
    
    -- ========================================
    -- UTILITAIRES DE FICHIERS
    -- ========================================
    
    -- Compresser un fichier
    compressFile = function(inputPath, outputPath, format)
        print("Compression de: " .. inputPath)
        
        -- Lire le fichier source
        local content = VFS.readFile(inputPath)
        if not content then
            print("Erreur: Impossible de lire le fichier source")
            return false
        end
        
        -- Compresser
        local compressed = Compressor.compressAdvanced(content, format)
        
        -- Sauvegarder
        local serialized = textutils.serialize(compressed)
        VFS.writeFile(outputPath, serialized)
        
        print("Compression terminée:")
        print("  Taille originale: " .. compressed.originalSize .. " octets")
        print("  Taille compressée: " .. compressed.compressedSize .. " octets")
        print("  Ratio: " .. compressed.ratio .. "%")
        print("  Algorithme: " .. compressed.algorithm)
        print("  Fichier: " .. outputPath)
        
        return true
    end,
    
    -- Décompresser un fichier
    decompressFile = function(inputPath, outputPath)
        print("Décompression de: " .. inputPath)
        
        -- Lire le fichier compressé
        local content = VFS.readFile(inputPath)
        if not content then
            print("Erreur: Impossible de lire le fichier compressé")
            return false
        end
        
        -- Désérialiser
        local compressed = textutils.unserialize(content)
        if not compressed then
            print("Erreur: Format de fichier compressé invalide")
            return false
        end
        
        -- Décompresser
        local decompressed = Compressor.decompressAdvanced(compressed)
        
        -- Sauvegarder
        VFS.writeFile(outputPath, decompressed)
        
        print("Décompression terminée:")
        print("  Taille originale: " .. compressed.originalSize .. " octets")
        print("  Taille décompressée: " .. #decompressed .. " octets")
        print("  Algorithme: " .. compressed.algorithm)
        print("  Fichier: " .. outputPath)
        
        return true
    end,
    
    -- Analyser un fichier compressé
    analyzeFile = function(filePath)
        print("Analyse de: " .. filePath)
        
        local content = VFS.readFile(filePath)
        if not content then
            print("Erreur: Fichier introuvable")
            return false
        end
        
        local compressed = textutils.unserialize(content)
        if not compressed then
            print("Erreur: Format de fichier invalide")
            return false
        end
        
        print("=== Informations de compression ===")
        print("Format: " .. compressed.format)
        print("Version: " .. compressed.version)
        print("Algorithme: " .. compressed.algorithm)
        print("Taille originale: " .. compressed.originalSize .. " octets")
        print("Taille compressée: " .. compressed.compressedSize .. " octets")
        print("Ratio de compression: " .. compressed.ratio .. "%")
        print("Date de compression: " .. os.date("%Y-%m-%d %H:%M:%S", compressed.compressedAt))
        
        return true
    end,
    
    -- ========================================
    -- COMPRESSION DE PAQUETS ADVOS
    -- ========================================
    
    -- Compresser un paquet AdvOS
    compressPackage = function(packagePath, outputPath)
        print("Compression du paquet: " .. packagePath)
        
        -- Lire le paquet
        local content = VFS.readFile(packagePath)
        if not content then
            print("Erreur: Paquet introuvable")
            return false
        end
        
        -- Désérialiser pour vérifier le format
        local package = textutils.unserialize(content)
        if not package then
            print("Erreur: Format de paquet invalide")
            return false
        end
        
        -- Compresser avec métadonnées spéciales
        local compressed = Compressor.compressAdvanced(content, "advp")
        compressed.packageInfo = {
            name = package.name,
            version = package.version,
            type = "advos_package"
        }
        
        -- Sauvegarder
        local serialized = textutils.serialize(compressed)
        VFS.writeFile(outputPath, serialized)
        
        print("Paquet compressé avec succès:")
        print("  Nom: " .. package.name)
        print("  Version: " .. package.version)
        print("  Ratio: " .. compressed.ratio .. "%")
        print("  Fichier: " .. outputPath)
        
        return true
    end,
    
    -- Décompresser un paquet AdvOS
    decompressPackage = function(compressedPath, outputPath)
        print("Décompression du paquet: " .. compressedPath)
        
        local content = VFS.readFile(compressedPath)
        if not content then
            print("Erreur: Fichier compressé introuvable")
            return false
        end
        
        local compressed = textutils.unserialize(content)
        if not compressed then
            print("Erreur: Format de fichier invalide")
            return false
        end
        
        -- Vérifier que c'est un paquet AdvOS
        if not compressed.packageInfo or compressed.packageInfo.type ~= "advos_package" then
            print("Erreur: Ce n'est pas un paquet AdvOS valide")
            return false
        end
        
        -- Décompresser
        local decompressed = Compressor.decompressAdvanced(compressed)
        
        -- Sauvegarder
        VFS.writeFile(outputPath, decompressed)
        
        print("Paquet décompressé avec succès:")
        print("  Nom: " .. compressed.packageInfo.name)
        print("  Version: " .. compressed.packageInfo.version)
        print("  Fichier: " .. outputPath)
        
        return true
    end,
    
    -- ========================================
    -- INTERFACE UTILISATEUR
    -- ========================================
    
    -- Afficher l'aide
    showHelp = function()
        print("=== Système de compression AdvOS ===")
        print("Usage:")
        print("  compress <input> <output> [format]  - Compresse un fichier")
        print("  decompress <input> <output>         - Décompresse un fichier")
        print("  analyze <file>                      - Analyse un fichier compressé")
        print("  package <input> <output>            - Compresse un paquet AdvOS")
        print("  unpackage <input> <output>         - Décompresse un paquet AdvOS")
        print("  benchmark <file>                    - Teste tous les algorithmes")
        print("  help                                - Affiche cette aide")
        print()
        print("Formats supportés:")
        print("  advz  - Format compressé AdvOS (par défaut)")
        print("  advp  - Format paquet AdvOS")
        print("  zip   - Format ZIP standard")
        print()
    end,
    
    -- Benchmark des algorithmes
    benchmark = function(filePath)
        print("Benchmark de: " .. filePath)
        
        local content = VFS.readFile(filePath)
        if not content then
            print("Erreur: Fichier introuvable")
            return false
        end
        
        print("Taille originale: " .. #content .. " octets")
        print()
        
        -- Test LZW
        local startTime = os.epoch("local")
        local lzwData = Compressor.compressLZW(content)
        local lzwTime = os.epoch("local") - startTime
        local lzwSize = #textutils.serialize(lzwData)
        
        -- Test RLE
        startTime = os.epoch("local")
        local rleData = Compressor.compressRLE(content)
        local rleTime = os.epoch("local") - startTime
        local rleSize = #rleData
        
        -- Test Huffman
        startTime = os.epoch("local")
        local huffmanData = Compressor.compressHuffman(content)
        local huffmanTime = os.epoch("local") - startTime
        local huffmanSize = #textutils.serialize(huffmanData.header) + #huffmanData.data
        
        -- Afficher les résultats
        print("=== Résultats du benchmark ===")
        print("LZW:")
        print("  Taille: " .. lzwSize .. " octets")
        print("  Ratio: " .. math.floor((1 - lzwSize / #content) * 100) .. "%")
        print("  Temps: " .. lzwTime .. "ms")
        print()
        
        print("RLE:")
        print("  Taille: " .. rleSize .. " octets")
        print("  Ratio: " .. math.floor((1 - rleSize / #content) * 100) .. "%")
        print("  Temps: " .. rleTime .. "ms")
        print()
        
        print("Huffman:")
        print("  Taille: " .. huffmanSize .. " octets")
        print("  Ratio: " .. math.floor((1 - huffmanSize / #content) * 100) .. "%")
        print("  Temps: " .. huffmanTime .. "ms")
        print()
        
        -- Recommandation
        local best = "LZW"
        local bestSize = lzwSize
        if rleSize < bestSize then
            best = "RLE"
            bestSize = rleSize
        end
        if huffmanSize < bestSize then
            best = "Huffman"
            bestSize = huffmanSize
        end
        
        print("Recommandation: " .. best .. " (" .. math.floor((1 - bestSize / #content) * 100) .. "% de compression)")
        
        return true
    end
}

-- ========================================
-- POINT D'ENTRÉE PRINCIPAL
-- ========================================

local function main()
    Compressor.init()
    
    local args = {...}
    
    if #args == 0 then
        Compressor.showHelp()
        return
    end
    
    local command = args[1]
    table.remove(args, 1)
    
    if command == "compress" then
        if #args < 2 then
            print("Usage: compress <input> <output> [format]")
            return
        end
        local format = args[3] or "advz"
        Compressor.compressFile(args[1], args[2], format)
        
    elseif command == "decompress" then
        if #args < 2 then
            print("Usage: decompress <input> <output>")
            return
        end
        Compressor.decompressFile(args[1], args[2])
        
    elseif command == "analyze" then
        if #args < 1 then
            print("Usage: analyze <file>")
            return
        end
        Compressor.analyzeFile(args[1])
        
    elseif command == "package" then
        if #args < 2 then
            print("Usage: package <input> <output>")
            return
        end
        Compressor.compressPackage(args[1], args[2])
        
    elseif command == "unpackage" then
        if #args < 2 then
            print("Usage: unpackage <input> <output>")
            return
        end
        Compressor.decompressPackage(args[1], args[2])
        
    elseif command == "benchmark" then
        if #args < 1 then
            print("Usage: benchmark <file>")
            return
        end
        Compressor.benchmark(args[1])
        
    elseif command == "help" then
        Compressor.showHelp()
        
    else
        print("Commande inconnue: " .. command)
        print("Utilisez 'help' pour voir les commandes disponibles")
    end
end

-- Exécuter si appelé directement
if not pcall(function() return _G.ADVOS_SHELL end) then
    main(...)
end

-- Exporter pour utilisation dans AdvOS
return Compressor 