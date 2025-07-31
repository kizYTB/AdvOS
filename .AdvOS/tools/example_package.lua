-- Exemple de paquet AdvOS pour tester la compression
-- Ce fichier peut être utilisé pour tester le système de compression

local examplePackage = {
    name = "example_app",
    version = "1.0.0",
    description = "Application d'exemple pour tester la compression",
    author = "AdvOS Team",
    created = os.epoch("local"),
    modified = os.epoch("local"),
    dependencies = {},
    files = {
        ["main.lua"] = [[
-- Application d'exemple
print("=== Application d'exemple ===")
print("Ceci est un test de compression")
print("Version: 1.0.0")
print("Auteur: AdvOS Team")

-- Variables d'environnement
print("APP_PATH: " .. (APP_PATH or "non défini"))
print("APP_DATA: " .. (APP_DATA or "non défini"))

-- Test de sauvegarde
if APP_DATA then
    local data = {
        lastRun = os.epoch("local"),
        version = "1.0.0",
        testData = "Ceci est un test"
    }
    
    local file = VFS.open(VFS.combine(APP_DATA, "test.json"), "w")
    if file then
        file.write(textutils.serializeJSON(data))
        file.close()
        print("Données sauvegardées avec succès")
    end
end

print("Test terminé!")
]],
        ["package.adv"] = [[
{
    "name": "example_app",
    "version": "1.0.0",
    "description": "Application d'exemple pour tester la compression",
    "author": "AdvOS Team",
    "created": ]] .. os.epoch("local") .. [[,
    "modified": ]] .. os.epoch("local") .. [[,
    "dependencies": [],
    "commands": {
        "test": {
            "description": "Lance le test de l'application",
            "code": "print('Test de commande réussi!')"
        }
    }
}
]],
        ["data/config.json"] = [[
{
    "appName": "example_app",
    "version": "1.0.0",
    "settings": {
        "debug": true,
        "autoSave": true,
        "compression": "enabled"
    }
}
]]
    },
    commands = {
        test = {
            description = "Lance le test de l'application",
            code = "print('Test de commande réussi!')"
        }
    }
}

-- Fonction pour créer le paquet d'exemple
local function createExamplePackage()
    print("=== Création du paquet d'exemple ===")
    
    -- Créer le répertoire
    local packageDir = "/.AdvOS/packages"
    if not VFS.exists(packageDir) then
        VFS.makeDir(packageDir)
    end
    
    -- Sauvegarder le paquet
    local packagePath = packageDir .. "/example_package.advp"
    local serialized = textutils.serialize(examplePackage)
    VFS.writeFile(packagePath, serialized)
    
    print("Paquet d'exemple créé: " .. packagePath)
    print("Taille: " .. #serialized .. " octets")
    
    return packagePath
end

-- Fonction pour tester la compression
local function testCompression()
    print("=== Test de compression ===")
    
    -- Créer le paquet d'exemple
    local packagePath = createExamplePackage()
    
    -- Charger le compresseur
    local compressorPath = "/.AdvOS/tools/compressor.lua"
    if not VFS.exists(compressorPath) then
        print("Erreur: Compresseur non trouvé")
        return false
    end
    
    local content = VFS.readFile(compressorPath)
    local env = createAdvosEnvironment()
    local fn, err = load(content, "compressor", "t", env)
    
    if not fn then
        print("Erreur de chargement: " .. err)
        return false
    end
    
    local success, Compressor = pcall(fn)
    if not success then
        print("Erreur d'exécution: " .. tostring(Compressor))
        return false
    end
    
    -- Tester la compression
    local compressedPath = "/.AdvOS/packages/example_package.advz"
    local success = Compressor.compressPackage(packagePath, compressedPath)
    
    if success then
        print("Compression réussie!")
        
        -- Analyser le fichier compressé
        Compressor.analyzeFile(compressedPath)
        
        -- Tester la décompression
        local decompressedPath = "/.AdvOS/packages/example_package_decompressed.advp"
        local success = Compressor.decompressPackage(compressedPath, decompressedPath)
        
        if success then
            print("Décompression réussie!")
            
            -- Comparer les fichiers
            local original = VFS.readFile(packagePath)
            local decompressed = VFS.readFile(decompressedPath)
            
            if original == decompressed then
                print("✅ Test de compression/décompression réussi!")
            else
                print("❌ Erreur: Les fichiers ne correspondent pas")
            end
        else
            print("❌ Erreur de décompression")
        end
    else
        print("❌ Erreur de compression")
    end
    
    return true
end

-- Exporter les fonctions
return {
    createExamplePackage = createExamplePackage,
    testCompression = testCompression,
    package = examplePackage
} 