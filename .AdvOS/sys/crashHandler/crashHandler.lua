-- crashHandler.lua - AdvOS Crash Handler (Version Corrigée)

-- Configuration
local backgroundColor = colors.blue
local textColor = colors.white
local textBackgroundColor = colors.black
local logoFile = "/.AdvOS/assets/crashHandler/logo.nfp"

-- Désactiver la capture d'événements pour éviter les interruptions
os.pullEvent = os.pullEventRaw

-- Fonction sécurisée pour vérifier l'existence d'un fichier
local function safeFileExists(path)
    local success, result = pcall(fs.exists, path)
    return success and result
end

-- Fonction sécurisée pour charger une image
local function safeLoadImage(path)
    if not paintutils then return nil end
    local success, image = pcall(paintutils.loadImage, path)
    return success and image or nil
end

-- Initialiser l'écran de manière sécurisée
local function initScreen()
    local success, err = pcall(function()
        term.setBackgroundColor(backgroundColor)
        term.clear()
        term.setCursorPos(1, 1)
    end)
    
    if not success then
        -- Fallback basique si term ne fonctionne pas
        print("Erreur d'initialisation de l'écran: " .. tostring(err))
    end
end

-- Fonction pour afficher le logo de manière sécurisée
local function displayLogo()
    local success, err = pcall(function()
        local logoX = 2
        local logoY = 2
        
        if safeFileExists(logoFile) then
            local logo = safeLoadImage(logoFile)
            if logo and paintutils then
                paintutils.drawImage(logo, logoX, logoY)
            else
                -- Afficher un logo ASCII simple si l'image ne charge pas
                term.setCursorPos(logoX, logoY)
                term.setTextColor(colors.red)
                term.write("AdvOS")
                term.setCursorPos(logoX, logoY + 1)
                term.write("=====")
            end
        else
            -- Logo ASCII de remplacement
            term.setCursorPos(2, 2)
            term.setTextColor(colors.red)
            term.write("  [!] AdvOS CRASH [!]  ")
            term.setCursorPos(2, 3)
            term.write("=====================")
        end
    end)
    
    if not success then
        -- Fallback ultra-basique
        print("ADVOS CRASH HANDLER")
    end
end

-- Fonction pour afficher le texte du crash de manière sécurisée
local function displayText()
    local success, err = pcall(function()
        local errorMessage = {
            "",
            "Ton ordinateur a planté.",
            "",
            "Nous sommes en train de rétablir le système d'AdvOS.",
            "",
            "Veuillez patienter..."
        }
        
        local screenWidth, screenHeight = term.getSize()
        local textStartY = 8
        
        term.setTextColor(textColor)
        
        for i, line in ipairs(errorMessage) do
            if textStartY + i - 1 <= screenHeight then
                term.setBackgroundColor(textBackgroundColor)
                term.setCursorPos(2, textStartY + i - 1)
                term.write(line)
                -- Remettre le fond bleu pour le reste de la ligne
                term.setBackgroundColor(backgroundColor)
            end
        end
    end)
    
    if not success then
        print("Erreur lors de l'affichage du texte: " .. tostring(err))
    end
end

-- Fonction pour dessiner une barre de progression sécurisée
local function drawLoadingBar(percentage, message)
    local success, err = pcall(function()
        local w, h = term.getSize()
        local barLength = math.max(10, w - 4) -- S'assurer que la barre a une taille minimale
        local filledLength = math.floor(barLength * math.max(0, math.min(1, percentage)))
        
        -- Effacer les anciennes lignes
        term.setCursorPos(1, h - 3)
        term.setBackgroundColor(backgroundColor)
        term.clearLine()
        term.setCursorPos(1, h - 2)
        term.clearLine()
        
        -- Afficher le message
        term.setCursorPos(2, h - 3)
        term.setTextColor(textColor)
        term.setBackgroundColor(backgroundColor)
        term.write(message .. " " .. math.floor(percentage * 100) .. "%")
        
        -- Dessiner la barre
        term.setCursorPos(2, h - 2)
        if filledLength > 0 then
            term.setBackgroundColor(colors.green)
            term.write(string.rep(" ", filledLength))
        end
        if filledLength < barLength then
            term.setBackgroundColor(colors.gray)
            term.write(string.rep(" ", barLength - filledLength))
        end
        
        -- Remettre le fond normal
        term.setBackgroundColor(backgroundColor)
    end)
    
    if not success then
        print("Progression: " .. math.floor(percentage * 100) .. "% - " .. message)
    end
end

-- Fonction pour simuler une progression avec gestion d'erreur
local function displayProgressWithMessage(duration, message)
    for i = 1, duration * 4 do
        local percentage = i / (duration * 4)
        drawLoadingBar(percentage, message)
        
        -- Sleep sécurisé
        local success, err = pcall(sleep, 0.25)
        if not success then
            -- Fallback sans sleep
            for j = 1, 100000 do end -- Petite pause
        end
    end
end

-- Fonction principale du crash handler
local function runCrashHandler()
    -- Initialisation
    initScreen()
    
    -- Afficher le logo et le texte
    displayLogo()
    displayText()
    
    -- Phase 1: Rétablissement
    displayProgressWithMessage(8, "Rétablissement du système")
    
    -- Petite pause
    local success, err = pcall(sleep, 1)
    if not success then
        for i = 1, 1000000 do end
    end
    
    -- Phase 2: Redémarrage
    displayProgressWithMessage(4, "Redémarrage du système")
    
    -- Pause finale
    local success, err = pcall(sleep, 1)
    if not success then
        for i = 1, 500000 do end
    end
    
    -- Message final
    local success, err = pcall(function()
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.green)
        print("AdvOS - Redémarrage terminé")
        term.setTextColor(colors.white)
    end)
    
    if not success then
        print("Redémarrage terminé")
    end
end

-- Point d'entrée principal avec gestion d'erreur globale
local function main()
    local success, err = pcall(runCrashHandler)
    
    if not success then
        -- En cas d'erreur dans le crash handler lui-même
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.red)
        print("ERREUR CRITIQUE DU CRASH HANDLER:")
        print(tostring(err))
        print("")
        print("Redémarrage forcé dans 3 secondes...")
        term.setTextColor(colors.white)
        
        -- Attente sécurisée
        for i = 3, 1, -1 do
            print(i .. "...")
            local success, err = pcall(sleep, 1)
            if not success then
                for j = 1, 1000000 do end
            end
        end
    end
    
    -- Redémarrage final sécurisé
    local success, err = pcall(os.reboot)
    if not success then
        -- Si os.reboot échoue, essayer de retourner au shell
        print("Impossible de redémarrer. Tentative de retour au shell...")
        local success2, err2 = pcall(shell.run, "shell")
        if not success2 then
            print("Erreur critique. Arrêt du programme.")
        end
    end
end

-- Lancer le programme principal
main()