-- ========================================
-- Installateur AdvOS
-- ========================================
-- Programme pour installer AdvOS depuis GitHub
-- Compatible avec les archives .advinstall

local Installer = {
    VERSION = "1.0.0",
    AUTHOR = "AdvOS Team",
    
    -- Configuration GitHub
    GITHUB_REPO = "kizYTB/AdvOS",
    RELEASE_URL = "https://api.github.com/repos/kizYTB/AdvOS/releases/latest",
    ASSETS_URL = "https://github.com/kizYTB/AdvOS/releases/download/",
    
    -- Configuration locale
    config = {
        tempDir = "/temp",
        installDir = "/.AdvOS",
        backupDir = "/.AdvOS_backup",
        logFile = "/install.log"
    },
    
    -- Initialisation
    init = function()
        print("=== Installateur AdvOS v" .. Installer.VERSION .. " ===")
        print("Auteur: " .. Installer.AUTHOR)
        print()
        
        -- Créer les dossiers nécessaires
        if not fs.exists(Installer.config.tempDir) then
            fs.makeDir(Installer.config.tempDir)
        end
        
        if not fs.exists(Installer.config.backupDir) then
            fs.makeDir(Installer.config.backupDir)
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
    
    -- Vérifier la connexion internet
    checkInternet = function()
        Installer.log("Vérification de la connexion internet...")
        
        local success = pcall(function()
            local response = http.get("https://httpbin.org/get")
            return response and response.getResponseCode() == 200
        end)
        
        if success then
            Installer.log("Connexion internet OK")
            return true
        else
            Installer.log("ERREUR: Pas de connexion internet")
            return false
        end
    end,
    
    -- Obtenir les informations de la dernière release
    getLatestReleaseInfo = function()
        Installer.log("Récupération des informations de release...")
        
        local url = Installer.RELEASE_URL
        local response = http.get(url)
        
        if not response then
            Installer.log("ERREUR: Impossible de contacter GitHub")
            return nil
        end
        
        local content = response.readAll()
        response.close()
        
        -- Parser le JSON (simplifié)
        local releaseInfo = {}
        
        -- Extraire le tag_name
        local tagMatch = content:match('"tag_name"%s*:%s*"([^"]+)"')
        if tagMatch then
            releaseInfo.tag_name = tagMatch
        end
        
        -- Extraire les assets
        local assets = {}
        for asset in content:gmatch('"browser_download_url"%s*:%s*"([^"]+)"') do
            if asset:match("%.advinstall$") then
                table.insert(assets, asset)
            end
        end
        
        releaseInfo.assets = assets
        
        if releaseInfo.tag_name and #releaseInfo.assets > 0 then
            Installer.log("Release trouvée: " .. releaseInfo.tag_name)
            Installer.log("Assets disponibles: " .. #releaseInfo.assets)
            return releaseInfo
        else
            Installer.log("ERREUR: Aucune release .advinstall trouvée")
            return nil
        end
    end,
    
    -- Télécharger un asset
    downloadAsset = function(url, filename)
        Installer.log("Téléchargement: " .. filename)
        
        local response = http.get(url)
        if not response then
            Installer.log("ERREUR: Impossible de télécharger " .. filename)
            return false
        end
        
        local content = response.readAll()
        response.close()
        
        local file = fs.open(filename, "wb")
        if not file then
            Installer.log("ERREUR: Impossible de créer " .. filename)
            return false
        end
        
        file.write(content)
        file.close()
        
        Installer.log("Téléchargement terminé: " .. filename .. " (" .. #content .. " bytes)")
        return true
    end,
    
    -- Sauvegarder l'installation existante
    backupExistingInstallation = function()
        Installer.log("Sauvegarde de l'installation existante...")
        
        if not fs.exists(Installer.config.installDir) then
            Installer.log("Aucune installation existante à sauvegarder")
            return true
        end
        
        local backupPath = Installer.config.backupDir .. "/backup_" .. os.epoch("local")
        
        -- Copier le dossier
        local function copyDir(src, dst)
            if not fs.exists(dst) then
                fs.makeDir(dst)
            end
            
            local items = fs.list(src)
            for _, item in ipairs(items) do
                local srcPath = fs.combine(src, item)
                local dstPath = fs.combine(dst, item)
                
                if fs.isDir(srcPath) then
                    copyDir(srcPath, dstPath)
                else
                    local file = fs.open(srcPath, "rb")
                    if file then
                        local content = file.readAll()
                        file.close()
                        
                        local dstFile = fs.open(dstPath, "wb")
                        if dstFile then
                            dstFile.write(content)
                            dstFile.close()
                        end
                    end
                end
            end
        end
        
        copyDir(Installer.config.installDir, backupPath)
        
        Installer.log("Sauvegarde créée: " .. backupPath)
        return true
    end,
    
    -- Installer l'archive
    installArchive = function(archivePath)
        Installer.log("Installation de l'archive...")
        
        -- Lire l'archive
        local file = fs.open(archivePath, "rb")
        if not file then
            Installer.log("ERREUR: Impossible d'ouvrir l'archive")
            return false
        end
        
        local content = file.readAll()
        file.close()
        
        -- Désérialiser l'archive
        local success, archive = pcall(textutils.unserialize, content)
        if not success or not archive then
            Installer.log("ERREUR: Format d'archive invalide")
            return false
        end
        
        -- Vérifier la structure
        if not archive.files then
            Installer.log("ERREUR: Archive corrompue (pas de fichiers)")
            return false
        end
        
        -- Supprimer l'ancienne installation
        if fs.exists(Installer.config.installDir) then
            fs.delete(Installer.config.installDir)
        end
        
        -- Créer le dossier d'installation
        fs.makeDir(Installer.config.installDir)
        
        -- Installer les fichiers
        local installedCount = 0
        for path, fileInfo in pairs(archive.files) do
            local fullPath = fs.combine(Installer.config.installDir, path)
            local dirPath = fs.getDir(fullPath)
            
            -- Créer le dossier parent si nécessaire
            if not fs.exists(dirPath) then
                fs.makeDir(dirPath)
            end
            
            -- Écrire le fichier
            local file = fs.open(fullPath, "wb")
            if file then
                file.write(fileInfo.content)
                file.close()
                installedCount = installedCount + 1
                Installer.log("Installé: " .. path)
            else
                Installer.log("ERREUR: Impossible d'écrire " .. path)
            end
        end
        
        Installer.log("Installation terminée: " .. installedCount .. " fichiers")
        return true
    end,
    
    -- Vérifier l'installation
    verifyInstallation = function()
        Installer.log("Vérification de l'installation...")
        
        local requiredFiles = {
            "boot.lua",
            "sys/shell/shell.lua"
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
        
        -- Supprimer les fichiers temporaires
        local tempFiles = fs.list(Installer.config.tempDir)
        for _, file in ipairs(tempFiles) do
            local filePath = fs.combine(Installer.config.tempDir, file)
            if not fs.isDir(filePath) then
                fs.delete(filePath)
            end
        end
        
        -- Supprimer le fichier de log
        if fs.exists(Installer.config.logFile) then
            fs.delete(Installer.config.logFile)
        end
        
        Installer.log("Nettoyage terminé")
    end,
    
    -- Installation complète
    install = function()
        Installer.log("Début de l'installation AdvOS...")
        
        -- Initialisation
        if not Installer.init() then
            return false
        end
        
        -- Vérifier la connexion internet
        if not Installer.checkInternet() then
            return false
        end
        
        -- Obtenir les informations de release
        local releaseInfo = Installer.getLatestReleaseInfo()
        if not releaseInfo then
            return false
        end
        
        -- Télécharger le premier asset .advinstall
        local assetUrl = releaseInfo.assets[1]
        local assetName = "advos_" .. releaseInfo.tag_name .. ".advinstall"
        local assetPath = fs.combine(Installer.config.tempDir, assetName)
        
        if not Installer.downloadAsset(assetUrl, assetPath) then
            return false
        end
        
        -- Sauvegarder l'installation existante
        if not Installer.backupExistingInstallation() then
            return false
        end
        
        -- Installer l'archive
        if not Installer.installArchive(assetPath) then
            return false
        end
        
        -- Vérifier l'installation
        if not Installer.verifyInstallation() then
            return false
        end
        
        -- Nettoyer
        Installer.cleanup()
        
        Installer.log("=== Installation AdvOS terminée avec succès ===")
        Installer.log("Version installée: " .. releaseInfo.tag_name)
        Installer.log("Dossier d'installation: " .. Installer.config.installDir)
        
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
        print("  1. Vérifier la connexion internet")
        print("  2. Télécharger la dernière release depuis GitHub")
        print("  3. Sauvegarder l'installation existante")
        print("  4. Installer AdvOS dans /.AdvOS")
        print("  5. Vérifier l'installation")
        print()
        print("Configuration:")
        print("  Repository: " .. Installer.GITHUB_REPO)
        print("  Dossier d'installation: " .. Installer.config.installDir)
        print("  Dossier de sauvegarde: " .. Installer.config.backupDir)
        print("  Fichier de log: " .. Installer.config.logFile)
    end
}

-- ========================================
-- POINT D'ENTRÉE PRINCIPAL
-- ========================================

-- Exécuter si appelé directement
if not pcall(function() return _G.ADVOS_SHELL end) then
    -- Installation par défaut
    local success = Installer.install()
    if not success then
        print("Installation échouée. Consultez le log: " .. Installer.config.logFile)
    end
end

-- Exporter pour utilisation dans AdvOS
return Installer 