-- boot.lua - Système de démarrage AdvOS

-- Configuration
local DEBUG_KEY = "d"  -- Touche pour entrer en mode debug
local BOOT_DELAY = 3   -- Délai en secondes pour appuyer sur la touche
local SHELL_PATH = "/.AdvOS/sys/shell/shell.lua"

-- Variables pour le mode debug
local debugMode = false
local w, h = term.getSize()

-- Sécurisation : Empêcher l'accès au disque CraftOS
local function secureAdvOS()
    print("Sécurisation d'AdvOS...")
    
    -- Désactiver l'accès aux disques CraftOS
    if disk then
        local original_disk = disk
        disk = {
            isPresent = function() return false end,
            getMountPath = function() return nil end,
            hasData = function() return false end,
            setLabel = function() return false end,
            getLabel = function() return "" end,
            getID = function() return 0 end,
            getData = function() return nil end,
            setData = function() return false end
        }
        print("Accès aux disques CraftOS désactivé")
    end
    
    -- Désactiver l'accès aux périphériques de stockage
    if peripheral then
        local original_peripheral = peripheral
        peripheral = setmetatable({}, {
            __index = function(t, k)
                if k == "find" then
                    return function() return {} end
                elseif k == "wrap" then
                    return function() return nil end
                elseif k == "getNames" then
                    return function() return {} end
                else
                    return original_peripheral[k]
                end
            end
        })
        print("Accès aux périphériques de stockage désactivé")
    end
    
    -- Rediriger fs vers VFS (sera configuré plus tard)
    if fs then
        local original_fs = fs
        _G.fs_original = original_fs
        print("fs sauvegardé dans fs_original")
    end
    
    print("Sécurisation terminée")
end

-- Fonction pour l'animation de démarrage
local function bootAnimation()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Logo AdvOS
    local centerY = math.floor(h / 2) - 3
    term.setTextColor(colors.blue)
    term.setCursorPos(math.floor((w - 35) / 2), centerY)
    print(" █████╗ ██████╗ ██╗   ██╗ ██████╗ ███████╗")
    term.setCursorPos(math.floor((w - 35) / 2), centerY + 1)
    print("██╔══██╗██╔══██╗██║   ██║██╔═══██╗██╔════╝")
    term.setCursorPos(math.floor((w - 35) / 2), centerY + 2)
    print("███████║██║  ██║██║   ██║██║   ██║███████╗")
    term.setCursorPos(math.floor((w - 35) / 2), centerY + 3)
    print("██╔══██║██║  ██║╚██╗ ██╔╝██║   ██║╚════██║")
    term.setCursorPos(math.floor((w - 35) / 2), centerY + 4)
    print("██║  ██║██████╔╝ ╚████╔╝ ╚██████╔╝███████║")
    
    -- Message de démarrage
    term.setCursorPos(1, h - 2)
    term.setTextColor(colors.white)
    write("Appuyez sur '" .. string.upper(DEBUG_KEY) .. "' pour le mode debug (")
    
    -- Compte à rebours
    for i = BOOT_DELAY, 1, -1 do
        term.setCursorPos(w - 10, h - 2)
        write(tostring(i) .. " sec)")
        
        local timer = os.startTimer(1)
        while true do
            local event, param = os.pullEvent()
            if event == "timer" and param == timer then
                break
            elseif event == "char" and param:lower() == DEBUG_KEY then
                debugMode = true
                break
            end
        end
        
        if debugMode then
            break
        end
    end
    
    return debugMode
end

-- Fonction pour le mode debug
local function runDebugMode()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    
    term.setTextColor(colors.red)
    print("=== MODE DEBUG ===")
    term.setTextColor(colors.yellow)
    print("Commandes disponibles:")
    print("- shell       : Lance le shell normal")
    print("- reboot      : Redémarre le système")
    print("- exit        : Quitte le mode debug")
    print("- clear       : Efface l'écran")
    print("- help        : Affiche cette aide")
    print()
    term.setTextColor(colors.white)
    
    while true do
        term.setTextColor(colors.red)
        write("DEBUG> ")
        term.setTextColor(colors.white)
        
        local input = read()
        local command = input:lower()
        
        if command == "shell" then
            shell.run(SHELL_PATH)
        elseif command == "reboot" then
            os.reboot()
        elseif command == "exit" then
            break
        elseif command == "clear" then
            term.clear()
            term.setCursorPos(1, 1)
        elseif command == "help" then
            term.setTextColor(colors.yellow)
            print("Commandes disponibles:")
            print("- shell       : Lance le shell normal")
            print("- reboot      : Redémarre le système")
            print("- exit        : Quitte le mode debug")
            print("- clear       : Efface l'écran")
            print("- help        : Affiche cette aide")
            term.setTextColor(colors.white)
        else
            -- Empêcher l'exécution de programmes sur le disque CraftOS
            if command:match("^/") or command:match("^disk/") or command:match("^rom/") then
                term.setTextColor(colors.red)
                print("Interdit : Accès au disque CraftOS bloqué")
                term.setTextColor(colors.white)
            else
                -- Essayer d'exécuter comme du Lua (seulement dans AdvOS)
                local func, err = load(input)
                if func then
                    local ok, result = pcall(func)
                    if not ok then
                        term.setTextColor(colors.red)
                        print("Erreur: " .. tostring(result))
                        term.setTextColor(colors.white)
                    elseif result ~= nil then
                        print(tostring(result))
                    end
                else
                    term.setTextColor(colors.red)
                    print("Commande inconnue. Tapez 'help' pour la liste des commandes.")
                    term.setTextColor(colors.white)
                end
            end
        end
    end
end

-- Programme principal
-- Sécuriser AdvOS avant tout
secureAdvOS()

if bootAnimation() then
    runDebugMode()
end

-- Lancer le shell normal si on n'est pas en debug ou après avoir quitté le debug
shell.run(SHELL_PATH)