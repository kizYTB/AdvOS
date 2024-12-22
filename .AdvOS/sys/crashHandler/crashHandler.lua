-- Définir les couleurs
local backgroundColor = colors.blue -- Fond bleu
local textColor = colors.white -- Texte blanc
local textBackgroundColor = colors.black -- Fond noir pour le texte
local logoFile = "/.AdvOS/assets/crashHandler/logo.nfp" -- Nom du fichier du logo (assurez-vous qu'il soit dans le répertoire du programme)

os.pullEvent = os.pullEventRaw

-- Initialiser l'écran
term.setBackgroundColor(backgroundColor) -- Définir le fond bleu
term.clear() -- Effacer l'écran

-- Fonction pour afficher le texte du BSOD
function displayText()
    -- Texte du BSOD (simulé, inspiré de Windows 10)
    local errorMessage = [[
Ton Ordinateur a plenté,

Nous somme entrain de retablir le system d'AdvOS 
    ]]

    -- Calculer la taille du texte
    local screenWidth, screenHeight = term.getSize()
    local textLines = {}

    -- Diviser le message en lignes
    for line in string.gmatch(errorMessage, "[^\n]+") do
        table.insert(textLines, line)
    end

    -- Calculer la position de départ du texte pour qu'il soit bien espacé et aligné à gauche
    local textStartY = 12  -- Augmenter la valeur pour espacer davantage le texte du logo

    -- Afficher le texte ligne par ligne, avec fond noir
    term.setTextColor(textColor)
    for i, line in ipairs(textLines) do
        -- Mettre le fond noir pour chaque ligne
        term.setBackgroundColor(textBackgroundColor)
        term.setCursorPos(2, textStartY + i - 1)  -- Aligné à gauche
        term.write(line)
    end
end

-- Fonction pour afficher le logo
function displayLogo()
    -- Afficher le logo dans le coin supérieur gauche (au début)
    local logoX = 2
    local logoY = 2

    -- Vérifier si le fichier du logo existe et afficher
    if fs.exists(logoFile) then
        local logo = paintutils.loadImage(logoFile)  -- Charger l'image .nfp
        paintutils.drawImage(logo, logoX, logoY)  -- Dessiner l'image au bon endroit
    else
        print("Erreur: le fichier du logo est introuvable.")
    end
end

local function drawLoadingBar(percentage)
    local w, h = term.getSize()
    local barLength = w - 4
    local filledLength = math.floor(barLength * percentage)
    term.setCursorPos(2, h - 2)
    term.setBackgroundColor(colors.green)
    term.write(string.rep(" ", filledLength))
    term.setBackgroundColor(colors.black)
    term.write(string.rep(" ", barLength - filledLength))
    term.setCursorPos(2, h - 3)
    term.setTextColor(textColor)
    term.write("Rétablisement du system " .. math.floor(percentage * 100) .. "%")
end

-- Afficher le logo et le texte du BSOD
displayLogo()  -- Afficher le logo
displayText()  -- Afficher le texte

-- Fonction pour afficher le spinner et la barre de progression
function displaySpinnerWithProgress(duration)
    local w, h = term.getSize()
    local centerX, centerY = math.floor(w / 2), math.floor(h / 2)

    for i = 1, duration * 4 do
        -- Efface l'ancienne barre et pourcentage avant de dessiner
        term.setCursorPos(2, h - 3)  -- Déplacer le curseur au-dessus de la barre
        term.setBackgroundColor(colors.blue)  -- Réinitialiser le fond à bleu pour effacer
        term.clearLine()  -- Effacer la ligne de texte précédente

        term.setCursorPos(centerX, centerY)
        term.setTextColor(textColor)
        drawLoadingBar(i / (duration * 4))  -- Afficher la barre de progression
        sleep(0.25)
    end
end

-- Afficher le spinner et le pourcentage
displaySpinnerWithProgress(10)

-- Laisser la barre de progression affichée pendant un moment
sleep(2)  -- Attendre 2 secondes avant de passer à la phase suivante

-- Fonction pour afficher la barre de progression du redémarrage
local function rebootingbar(percentage)
    local w, h = term.getSize()
    local barLength = w - 4
    local filledLength = math.floor(barLength * percentage)
    term.setCursorPos(2, h - 2)
    term.setBackgroundColor(colors.green)
    term.write(string.rep(" ", filledLength))
    term.setBackgroundColor(colors.black)
    term.write(string.rep(" ", barLength - filledLength))
    term.setCursorPos(2, h - 3)
    term.setTextColor(textColor)
    term.write("Redémarrge du system " .. math.floor(percentage * 100) .. "%")
end

-- Fonction pour afficher le spinner de redémarrage
function rebooutingspinner(duration)
    local w, h = term.getSize()
    local centerX, centerY = math.floor(w / 2), math.floor(h / 2)

    for i = 1, duration * 4 do
        -- Efface l'ancienne barre de progression du rétablissement
        term.setCursorPos(2, h - 3)
        term.setBackgroundColor(colors.blue)  -- Réinitialiser le fond à bleu pour effacer
        term.clearLine()  -- Effacer la ligne précédente

        term.setCursorPos(centerX, centerY)
        term.setTextColor(textColor)
        rebootingbar(i / (duration * 4))  -- Afficher la barre de progression du redémarrage
        sleep(0.25)
    end
end

-- Lance le processus de redémarrage
rebooutingspinner(4)

os.reboot()