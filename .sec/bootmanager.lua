local run = shell.run

-- Table des commandes principales
local commands = {}

-- Fonction pour ajouter une commande principale et ses sous-commandes
local function addCommand(mainCommand, subCommands)
    commands[mainCommand] = subCommands
end

-- Ajouter des sous-commandes pour "disk"
addCommand("disk", {
    on = function()
        print("Disk is now ON.")
        settings.set("shell.allow_disk_startup", true)
		settings.save()
    end,
    off = function()
        print("Disk is now OFF.")
        settings.set("shell.allow_disk_startup", false)
		settings.save()
    end
})

addCommand("password", {
    reset = function()
        run("/.sec/resetpass.lua")
    end,
})

addCommand("status", {
    [""] = function()
        print("Erreur de récupération")
	end
})

addCommand("help", {
    [""] = function()
        print("Liste des commandes principales :")
        for mainCommand, subCommands in pairs(commands) do
            print("- " .. mainCommand)
            if type(subCommands) == "table" then
                for subCommand, _ in pairs(subCommands) do
                    print("   - " .. mainCommand .. " " .. subCommand)
                end
            end
        end
    end
})

-- Fonction principale
local args = {...}

if #args < 1 then
    print("Usage : <commande> [arguement]")
    print("Exemple : 'disk on' ou 'disk off'")
    return
end

-- Identifier la commande principale et la sous-commande
local mainCommand = args[1]
local subCommand = args[2] or ""

if commands[mainCommand] then
    local subCommands = commands[mainCommand]
    if type(subCommands) == "table" and subCommands[subCommand] then
        subCommands[subCommand]()
    else
        print("Sous-commande inconnue : " .. (subCommand ~= "" and subCommand or "aucune"))
        print("Utilisez 'help' pour voir les commandes disponibles.")
    end
else
    print("Commande inconnue : " .. mainCommand)
    print("Utilisez 'help' pour voir les commandes disponibles.")
end
