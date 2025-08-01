-- ========================================
-- Lanceur CraftOS pour l'installateur AdvOS
-- ========================================

local args = {...}
local command = args[1] or "install"

print("=== Lanceur Installateur AdvOS ===")
print("Commande: " .. command)
print()

if command == "help" then
    -- Afficher l'aide
    shell.run("install_advos.lua", "help")
elseif command == "install" then
    -- Installer AdvOS
    print("Démarrage de l'installation AdvOS...")
    shell.run("install_advos.lua", "install")
else
    print("Commande inconnue: " .. command)
    print("Utilisez: install_advos_craftos help")
    print("ou: install_advos_craftos install")
end 