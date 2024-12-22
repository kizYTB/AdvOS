-- Fonction pour changer le mot de passe dans un programme dédié
local function changePassword(passwordFile)
    -- Vérifie si le fichier existe
    if fs.exists(passwordFile) then
        local file = fs.open(passwordFile, "r")
        local currentPassword = file.readLine()
        file.close()

        -- Demande à l'utilisateur de saisir l'ancien mot de passe
        print("Entrez l'ancien mot de passe :")
        local oldPassword = read("*")

        if oldPassword == currentPassword then
            -- Demande un nouveau mot de passe
            print("Entrez le nouveau mot de passe :")
            local newPassword = read("*")
            print("Confirmez le nouveau mot de passe :")
            local confirmPassword = read("*")

            if newPassword == confirmPassword then
                -- Sauvegarde du nouveau mot de passe
                local file = fs.open(passwordFile, "w")
                file.writeLine(newPassword)
                file.close()
                print("Mot de passe changé avec succès.")
            else
                print("Les mots de passe ne correspondent pas.")
            end
        else
            print("L'ancien mot de passe est incorrect.")
        end
    else
        print("Aucun mot de passe défini. Vous devez d'abord définir un mot de passe.")
    end
end

changePassword("/.sec/pass/data.txt")
