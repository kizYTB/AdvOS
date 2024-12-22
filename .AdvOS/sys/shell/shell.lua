-- advShell.lua
-- Configuration
local SHELL_NAME = "AdvOS"
local PROMPT_CHAR = ">"
local LOG_FILE = "shell_log.txt"

-- Couleurs
local colors = {
    prompt = colors.yellow,
    text = colors.white,
    error = colors.red,
    success = colors.green,
    path = colors.lightBlue
}

-- Variables globales
local currentPath = ""
local history = {}

-- Fonction pour écrire dans le log
local function writeLog(message)
    local file = fs.open(LOG_FILE, "a")
    if file then
        file.write(os.date("[%Y-%m-%d %H:%M:%S] ") .. message .. "\n")
        file.close()
    end
end

-- Fonction pour résoudre le chemin complet
local function resolvePath(path)
    -- Si le chemin commence par /, c'est un chemin absolu
    if path:sub(1,1) == "/" then
        return path
    else
        -- Sinon, c'est un chemin relatif, on le combine avec le chemin actuel
        return fs.combine(currentPath, path)
    end
end

-- Afficher le prompt
local function displayPrompt()
    term.setTextColor(colors.prompt)
    write(SHELL_NAME .. "/" .. currentPath .. PROMPT_CHAR)
    term.setTextColor(colors.text)
end

-- Gérer les commandes
local function handleCommand(command)
    local words = {}
    for word in command:gmatch("%S+") do
        table.insert(words, word)
    end
    
    if #words == 0 then return end
    
    local cmd = words[1]:lower()
    
    if cmd == "clear" then
        term.clear()
        term.setCursorPos(1,1)
    elseif cmd == "cd" then
        if words[2] then
            -- Résoudre le chemin complet
            local targetPath = resolvePath(words[2])
            -- Vérifier si le chemin existe
            if fs.exists(targetPath) and fs.isDir(targetPath) then
                currentPath = targetPath
                if currentPath:sub(1,1) == "/" then
                    currentPath = currentPath:sub(2)  -- Enlever le / initial pour l'affichage
                end
            else
                term.setTextColor(colors.error)
                print("Chemin invalide: " .. targetPath)
                term.setTextColor(colors.text)
            end
        end
    elseif cmd == "ls" or cmd == "dir" then
        local path = words[2] and resolvePath(words[2]) or currentPath
        if fs.exists(path) then
            local list = fs.list(path)
            for _, item in ipairs(list) do
                local fullPath = fs.combine(path, item)
                if fs.isDir(fullPath) then
                    term.setTextColor(colors.path)
                    print("<DIR> " .. item)
                else
                    term.setTextColor(colors.text)
                    print("      " .. item)
                end
            end
        end
    elseif cmd == "pwd" then
        -- Nouvelle commande pour afficher le chemin actuel
        print(currentPath == "" and "/" or "/" .. currentPath)
    else
        -- Tenter d'exécuter un programme
        local program = resolvePath(words[1])
        if fs.exists(program) and not fs.isDir(program) then
            local success, err = pcall(function()
                shell.run(program, table.unpack(words, 2))
            end)
            if not success then
                term.setTextColor(colors.error)
                print("Erreur lors de l'exécution: " .. tostring(err))
                writeLog("Erreur d'exécution - Programme: " .. program .. " - " .. tostring(err))
                term.setTextColor(colors.text)
            end
        else
            term.setTextColor(colors.error)
            print("Commande non reconnue: " .. cmd)
            term.setTextColor(colors.text)
        end
    end
end

-- Boucle principale du shell
local function mainLoop()
    while true do
        term.setTextColor(colors.text)
        displayPrompt()
        
        -- Capture des erreurs lors de la lecture de l'entrée
        local success, input = pcall(function()
            return read()
        end)
        
        if success and input then
            if input:len() > 0 then
                table.insert(history, input)
                -- Capture des erreurs lors de l'exécution des commandes
                local cmdSuccess, cmdErr = pcall(function()
                    handleCommand(input)
                end)
                
                if not cmdSuccess then
                    term.setTextColor(colors.error)
                    print("Erreur shell: " .. tostring(cmdErr))
                    writeLog("Erreur shell: " .. tostring(cmdErr))
                end
            end
        else
            term.setTextColor(colors.error)
            print("Erreur de lecture: " .. tostring(input))
            writeLog("Erreur de lecture: " .. tostring(input))
        end
        
        -- Petit délai pour éviter une utilisation excessive du CPU
        os.sleep(0.05)
    end
end

-- Fonction de démarrage qui ne s'arrête jamais
while true do
    term.clear()
    term.setCursorPos(1,1)
    print("AdvOS Shell - Version Permanente")
    print("----------------------------------------")
    
    local success, err = pcall(mainLoop)
    
    if not success then
        term.setTextColor(colors.error)
        print("Erreur fatale du shell: " .. tostring(err))
        writeLog("Erreur fatale: " .. tostring(err))
        print("Redémarrage du shell dans 3 secondes...")
        os.sleep(3)
    end
end