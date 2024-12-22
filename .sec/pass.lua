-- Définir le nom du fichier contenant le mot de passe
local passwordFile = "/.sec/pass/data.txt"

os.pullEvent = os.pullEventRaw

shell.setAlias("boot","/.sec/bootmanager.lua")

local function br()
   print() 
end

-- Fonction pour enregistrer un mot de passe dans un fichier
local function savePassword(newPassword)
    local file = fs.open(passwordFile, "w")
    if file then
        file.writeLine(newPassword)
        file.close()
    else
        br()
        print("Erreur lors de l'ouverture du fichier pour l'écriture.")
        sleep(3)
        os.reboot()
    end
end

-- Fonction pour charger le mot de passe depuis le fichier
local function loadPassword()
    if fs.exists(passwordFile) then
        local file = fs.open(passwordFile, "r")
        if file then
            local savedPassword = file.readLine()
            file.close()
            return savedPassword
        else
            br()
            print("Erreur lors de l'ouverture du fichier pour la lecture.")
            sleep(3)
            os.reboot()
        end
    else
        return nil
    end
end

-- Fonction pour demander un mot de passe à l'utilisateur
local function askPassword()
    br()
    term.clear()
    term.setCursorPos(1,1)
    term.write("Veuillez entrer votre mot de passe : ")
    local enteredPassword = read("*")  -- Lecture sécurisée du mot de passe
    return enteredPassword
end

-- Fonction pour configurer un nouveau mot de passe
local function setNewPassword()
    term.clear()
    term.setCursorPos(1, 1)
    print("C'est votre première utilisation ! Veuillez définir un nouveau mot de passe.")
    br()
    term.write("Entrez votre nouveau mot de passe : ")
    local newPassword = read("*")  -- Lecture du mot de passe
    savePassword(newPassword)
    br()-- Sauvegarde du mot de passe
    print("Mot de passe enregistré avec succès !")
    sleep(3)
    os.reboot()
end

-- Fonction pour accéder au système après validation du mot de passe
local function accessSystem()
    term.clear()
    term.setCursorPos(1, 1)
    print("Accès au système accordé.")
    sleep(2)
   	shell.run("shell")
    -- Ici, vous pouvez ajouter des fonctionnalités supplémentaires pour l'accès au shell ou autres
end

-- Fonction principale
local function main()
    local storedPassword = loadPassword()

    if storedPassword == nil then
        -- Si le mot de passe n'est pas encore configuré, demandez à l'utilisateur de le définir
        setNewPassword()
    end

    -- Demander à l'utilisateur de saisir le mot de passe
    local passwordAttempt = askPassword()

    -- Vérifier si le mot de passe est correct
    if passwordAttempt == storedPassword then
        accessSystem()
    else
        br()
        print("Mot de passe incorrect !")
        sleep(3)
        os.reboot()
    end
end

-- Exécution du programme
main()
