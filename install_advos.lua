-- ========================================
-- Installateur AdvOS
-- ========================================
-- Programme d'installation d'AdvOS depuis GitHub
-- Télécharge et installe AdvOS automatiquement

local Installer = {
    VERSION = "1.0.0",
    GITHUB_REPO = "advos/advos",  -- À modifier selon votre repo
    RELEASE_URL = "https://api.github.com/repos/KizYTB/AdvOS/releases/latest",
    ASSETS_URL = "https://github.com/KizYTB/AdvOS/releases/download/",
    
    -- Configuration
    config = {
        tempDir = "/temp",
        installDir = "/.AdvOS",
        backupDir = "/.AdvOS_backup",
        logFile = "/install.log"
    },
    
    -- Initialisation
    init = function()
        print("=== Installateur AdvOS v" .. Installer.VERSION .. " ===")
        print("Ce programme va installer AdvOS depuis GitHub")
        print()
        
        -- Créer les dossiers temporaires
        if not fs.exists(Installer.config.tempDir) then
            fs.makeDir(Installer.config.tempDir)
        end
        
        return true
    end,
    
    -- Logger
    log = function(message)
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local logEntry = "[" .. timestamp .. "] " .. message
        
        print(logEntry)
        
        -- Sauvegarder dans le fichier de log
        local file = fs.open(Installer.config.logFile, "a")
        if file then
            file.writeLine(logEntry)
            file.close()
        end
    end,
    
    -- Vérifier la connectivité Internet
    checkInternet = function()
        Installer.log("Vérification de la connectivité Internet...")
        
        local response = http.get("https://httpbin.org/get")
        if not response then
            Installer.log("ERREUR: Pas de connexion Internet")
            return false
        end
        
        response.close()
        Installer.log("Connexion Internet OK")
        return true
    end,
    
    -- Récupérer les informations de la dernière release
    getLatestRelease = function()
        Installer.log("Récupération des informations de la dernière release...")
        
        local response = http.get(Installer.RELEASE_URL)
        if not response then
            Installer.log("ERREUR: Impossible de récupérer les informations de release")
            return false
        end
        
        local content = response.readAll()
        response.close()
        
        local success, release = pcall(textutils.unserializeJSON, content)
        if not success or not release then
            Installer.log("ERREUR: Format de réponse GitHub invalide")
            return false
        end
        
        Installer.log("Release trouvée: " .. release.tag_name)
        Installer.log("Description: " .. (release.body or "Aucune description"))
        
        return release
    end,
    
    -- Trouver le fichier .advinstall dans les assets
    findAdvInstallFile = function(release)
        Installer.log("Recherche du fichier .advinstall...")
        
        for _, asset in ipairs(release.assets) do
            if asset.name:match("%.advinstall$") then
                Installer.log("Fichier trouvé: " .. asset.name)
                Installer.log("Taille: " .. asset.size .. " bytes")
                Installer.log("Téléchargements: " .. asset.download_count)
                return asset
            end
        end
        
        Installer.log("ERREUR: Aucun fichier .advinstall trouvé dans la release")
        return false
    end,
    
    -- Télécharger le fichier .advinstall
    downloadAdvInstall = function(asset, release)
        local downloadUrl = asset.browser_download_url
        local localPath = fs.combine(Installer.config.tempDir, asset.name)
        
        Installer.log("Téléchargement de " .. asset.name .. "...")
        Installer.log("URL: " .. downloadUrl)
        
        local response = http.get(downloadUrl)
        if not response then
            Installer.log("ERREUR: Impossible de télécharger le fichier")
            return false
        end
        
        local content = response.readAll()
        response.close()
        
        -- Sauvegarder le fichier
        local file = fs.open(localPath, "wb")
        if not file then
            Installer.log("ERREUR: Impossible de sauvegarder le fichier")
            return false
        end
        
        file.write(content)
        file.close()
        
        Installer.log("Téléchargement terminé: " .. localPath)
        Installer.log("Taille téléchargée: " .. #content .. " bytes")
        
        return localPath
    end,
    
    -- Créer une sauvegarde de l'installation actuelle
    createBackup = function()
        Installer.log("Création d'une sauvegarde de l'installation actuelle...")
        
        if fs.exists(Installer.config.installDir) then
            local backupPath = Installer.config.backupDir .. "_" .. os.epoch("local")
            
            if fs.exists(backupPath) then
                fs.delete(backupPath)
            end
            
            fs.move(Installer.config.installDir, backupPath)
            Installer.log("Sauvegarde créée: " .. backupPath)
            return backupPath
        else
            Installer.log("Aucune installation existante à sauvegarder")
            return nil
        end
    end,
    
    -- Installer AdvOS depuis le fichier .advinstall
    installAdvOS = function(advInstallPath)
        Installer.log("Installation d'AdvOS depuis " .. advInstallPath .. "...")
        
        -- Lire le fichier .advinstall
        local file = fs.open(advInstallPath, "rb")
        if not file then
            Installer.log("ERREUR: Impossible d'ouvrir le fichier .advinstall")
            return false
        end
        
        local content = file.readAll()
        file.close()
        
        -- Désérialiser l'archive
        local success, archive = pcall(textutils.unserialize, content)
        if not success or not archive then
            Installer.log("ERREUR: Format de fichier .advinstall invalide")
            return false
        end
        
        Installer.log("Archive détectée:")
        Installer.log("  Version: " .. (archive.version or "Inconnue"))
        Installer.log("  Fichiers: " .. (archive.fileCount or 0))
        Installer.log("  Créé: " .. os.date("%Y-%m-%d %H:%M:%S", archive.created or 0))
        
        -- Créer le dossier d'installation
        if not fs.exists(Installer.config.installDir) then
            fs.makeDir(Installer.config.installDir)
        end
        
        -- Installer les fichiers
        local installed = 0
        local errors = 0
        
        for path, data in pairs(archive.files) do
            local fullPath = fs.combine(Installer.config.installDir, path)
            local dir = fs.getDir(fullPath)
            
            -- Créer le dossier parent si nécessaire
            if not fs.exists(dir) then
                fs.makeDir(dir)
            end
            
            -- Écrire le fichier
            local file = fs.open(fullPath, "w")
            if file then
                file.write(data.content)
                file.close()
                installed = installed + 1
                Installer.log("Installé: " .. path)
            else
                errors = errors + 1
                Installer.log("ERREUR: Impossible d'installer " .. path)
            end
        end
        
        Installer.log("Installation terminée:")
        Installer.log("  Fichiers installés: " .. installed)
        Installer.log("  Erreurs: " .. errors)
        
        return errors == 0
    end,
    
    -- Vérifier l'installation
    verifyInstallation = function()
        Installer.log("Vérification de l'installation...")
        
        local requiredFiles = {
            "boot.lua",
            "sys/shell/shell.lua",
            "tools/compressor.lua"
        }
        
        local missing = 0
        for _, file in ipairs(requiredFiles) do
            local path = fs.combine(Installer.config.installDir, file)
            if not fs.exists(path) then
                Installer.log("ERREUR: Fichier manquant: " .. file)
                missing = missing + 1
            else
                Installer.log("OK: " .. file)
            end
        end
        
        if missing == 0 then
            Installer.log("Installation vérifiée avec succès")
            return true
        else
            Installer.log("ERREUR: " .. missing .. " fichier(s) manquant(s)")
            return false
        end
    end,
    
    -- Nettoyer les fichiers temporaires
    cleanup = function()
        Installer.log("Nettoyage des fichiers temporaires...")
        
        local files = fs.list(Installer.config.tempDir)
        for _, file in ipairs(files) do
            local path = fs.combine(Installer.config.tempDir, file)
            if fs.exists(path) then
                fs.delete(path)
                Installer.log("Supprimé: " .. file)
            end
        end
        
        Installer.log("Nettoyage terminé")
    end,
    
    -- Installation complète
    install = function()
        Installer.log("Début de l'installation d'AdvOS...")
        
        -- Initialisation
        if not Installer.init() then
            return false
        end
        
        -- Vérifier la connectivité
        if not Installer.checkInternet() then
            return false
        end
        
        -- Récupérer les informations de release
        local release = Installer.getLatestRelease()
        if not release then
            return false
        end
        
        -- Trouver le fichier .advinstall
        local asset = Installer.findAdvInstallFile(release)
        if not asset then
            return false
        end
        
        -- Télécharger le fichier
        local advInstallPath = Installer.downloadAdvInstall(asset, release)
        if not advInstallPath then
            return false
        end
        
        -- Créer une sauvegarde
        local backupPath = Installer.createBackup()
        
        -- Installer AdvOS
        local success = Installer.installAdvOS(advInstallPath)
        if not success then
            Installer.log("ERREUR: Échec de l'installation")
            
            -- Restaurer la sauvegarde si elle existe
            if backupPath then
                Installer.log("Restauration de la sauvegarde...")
                if fs.exists(Installer.config.installDir) then
                    fs.delete(Installer.config.installDir)
                end
                fs.move(backupPath, Installer.config.installDir)
                Installer.log("Sauvegarde restaurée")
            end
            
            return false
        end
        
        -- Vérifier l'installation
        if not Installer.verifyInstallation() then
            Installer.log("ERREUR: Installation incomplète")
            return false
        end
        
        -- Nettoyer
        Installer.cleanup()
        
        Installer.log("=== Installation d'AdvOS terminée avec succès ===")
        Installer.log("Redémarrage dans 5 secondes...")
        
        os.sleep(5)
        os.reboot()
        
        return true
    end,
    
    -- Afficher l'aide
    showHelp = function()
        print("=== Installateur AdvOS ===")
        print("Usage:")
        print("  install_advos.lua install  - Installe AdvOS depuis GitHub")
        print("  install_advos.lua help     - Affiche cette aide")
        print()
        print("Le programme va:")
        print("  1. Télécharger la dernière release depuis GitHub")
        print("  2. Créer une sauvegarde de l'installation actuelle")
        print("  3. Installer AdvOS")
        print("  4. Vérifier l'installation")
        print("  5. Redémarrer le système")
        print()
        print("Configuration:")
        print("  Repository: " .. Installer.GITHUB_REPO)
        print("  Dossier d'installation: " .. Installer.config.installDir)
        print("  Fichier de log: " .. Installer.config.logFile)
    end
}

-- ========================================
-- POINT D'ENTRÉE PRINCIPAL
-- ========================================

local function main()
    local args = {...}
    
    if #args == 0 or args[1] == "help" then
        Installer.showHelp()
        return
    end
    
    local command = args[1]
    
    if command == "install" then
        local success = Installer.install()
        if not success then
            print("Installation échouée. Consultez le log: " .. Installer.config.logFile)
            return false
        end
        return true
        
    else
        print("Commande inconnue: " .. command)
        print("Utilisez 'help' pour voir les commandes disponibles")
        return false
    end
end

-- Exécuter si appelé directement
if not pcall(function() return _G.ADVOS_SHELL end) then
    main(...)
end

-- Exporter pour utilisation dans AdvOS
return Installer 