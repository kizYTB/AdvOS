-- Configuration
local SHELL_NAME = "AdvOS"
local PROMPT_CHAR = ">"
local LOG_FILE = "/.AdvOS/logs/shell_log.txt"
local VFS_DATA_FILE = "/.AdvOS/vfs/vfs_data.dat"
local FIRST_RUN_FLAG = "/.AdvOS/.first_run"
local CRASH_FLAG = "/.AdvOS/.crash_flag"
local MAX_CRASH_COUNT = 3

-- API globale advos complète (comme les librairies ComputerCraft)
_G.advos = _G.advos or {}

-- Rendre VFS global pour que tous les programmes puissent l'utiliser
_G.VFS = VFS

-- Gestion des processus en arrière-plan
advos.processes = advos.processes or {}
advos.processes.list = {}
advos.processes.nextId = 1

-- Fonction pour créer un nouvel environnement AdvOS
local function createAdvosEnvironment()
  local env = setmetatable({}, {__index = _G})
  
  -- Remplacer shell.run par advos.shell.run
  env.shell = {
    run = function(path, ...)
      return advos.shell.run(path, ...)
    end,
    exit = function()
      print("Interdit : impossible de quitter AdvOS.")
    end,
    dir = function()
      return currentPath
    end,
    setDir = function(path)
      currentPath = resolvePath(path)
    end
  }
  
  -- Remplacer os.exit
  env.os = setmetatable({}, {__index = os})
  env.os.exit = function()
    print("Interdit : impossible de quitter AdvOS.")
  end
  
  return env
end

-- advos.shell - Gestion des programmes
advos.shell = advos.shell or {}
function advos.shell.run(path, ...)
  local resolved = resolvePath(path)
  -- Autorise seulement les chemins dans le VFS AdvOS, sauf si ADVOS_PRIVILEGED est défini
  local isInVFS = resolved:find("^/%.?AdvOS/") or resolved:find("^%.?AdvOS/") or resolved:find("^/%.advos/") or resolved:find("^%.advos/")
  if not isInVFS and not _G.ADVOS_PRIVILEGED then
    print("Interdit : impossible de lancer un programme hors du VFS AdvOS.")
    return false
  end
  if not VFS.exists(resolved) then
    print("Fichier introuvable : " .. resolved)
    return false
  end
  
  -- Créer un environnement AdvOS sécurisé
  local env = createAdvosEnvironment()
  
  local fn, err = loadfile(resolved, "t", env)
  if not fn then
    print("Erreur de chargement : " .. err)
    return false
  end
  
  -- Récupérer les arguments varargs
  local args = {...}
  local ok, result = pcall(fn, table.unpack(args))
  if not ok then
    print("Erreur d'exécution : " .. tostring(result))
    return false
  end
  return true
end

-- advos.shell.runBackground - Exécution en arrière-plan
function advos.shell.runBackground(path, ...)
  local resolved = resolvePath(path)
  local isInVFS = resolved:find("^/%.?AdvOS/") or resolved:find("^%.?AdvOS/") or resolved:find("^/%.advos/") or resolved:find("^%.advos/")
  if not isInVFS and not _G.ADVOS_PRIVILEGED then
    print("Interdit : impossible de lancer un programme hors du VFS AdvOS.")
    return false
  end
  if not VFS.exists(resolved) then
    print("Fichier introuvable : " .. resolved)
    return false
  end
  
  -- Créer un processus en arrière-plan
  local processId = advos.processes.nextId
  advos.processes.nextId = advos.processes.nextId + 1
  
  local env = createAdvosEnvironment()
  
  -- Créer le processus
  local process = {
    id = processId,
    path = resolved,
    args = {...},
    env = env,
    status = "running",
    startTime = os.time(),
    output = {}
  }
  
  -- Fonction d'exécution en arrière-plan
  local function runProcess()
    local fn, err = loadfile(resolved, "t", env)
    if not fn then
      process.status = "error"
      process.error = err
      return
    end
    
    local ok, result = pcall(fn, table.unpack(process.args))
    if not ok then
      process.status = "error"
      process.error = tostring(result)
    else
      process.status = "completed"
      process.result = result
    end
    process.endTime = os.time()
  end
  
  -- Démarrer le processus en arrière-plan
  process.thread = runProcess
  advos.processes.list[processId] = process
  
  print("Processus " .. processId .. " démarré en arrière-plan: " .. resolved)
  return processId
end

-- advos.shell.listProcesses - Lister les processus
function advos.shell.listProcesses()
  print("Processus en cours:")
  print("ID\tStatus\t\tTemps\t\tProgramme")
  print("--\t------\t\t-----\t\t---------")
  
  for id, process in pairs(advos.processes.list) do
    local timeStr = "en cours"
    if process.endTime then
      timeStr = (process.endTime - process.startTime) .. "s"
    end
    
    print(id .. "\t" .. process.status .. "\t\t" .. timeStr .. "\t\t" .. process.path)
  end
end

-- advos.shell.killProcess - Tuer un processus
function advos.shell.killProcess(processId)
  local process = advos.processes.list[processId]
  if not process then
    print("Processus " .. processId .. " introuvable")
    return false
  end
  
  if process.status == "running" then
    process.status = "killed"
    process.endTime = os.time()
    print("Processus " .. processId .. " tué")
  else
    print("Processus " .. processId .. " déjà terminé")
  end
  
  return true
end

-- advos.launchStartup - Lancement automatique du startup
advos.launchStartup = function()
  local startupPath = ".advos/os/startup"
  if VFS.exists(startupPath) then
    print("Lancement automatique de .advos/os/startup...")
    local success, err = pcall(function()
      advos.shell.run(startupPath)
    end)
    if not success then
      print("Erreur lors du lancement de startup: " .. tostring(err))
    end
  end
end

-- advos.require - Système de modules AdvOS amélioré
advos.require = advos.require or {}
function advos.require(moduleName)
  -- Chercher dans différents emplacements
  local searchPaths = {
    -- Modules système
    "/.AdvOS/system/" .. moduleName,
    -- Modules d'apps (nomapp.module)
    "/.AdvOS/apps/" .. moduleName,
    -- Modules dans le VFS racine
    "/" .. moduleName,
    -- Avec extension .lua
    "/.AdvOS/system/" .. moduleName .. ".lua",
    "/.AdvOS/apps/" .. moduleName .. ".lua",
    "/" .. moduleName .. ".lua"
  }
  
  local resolved = nil
  for _, path in ipairs(searchPaths) do
    if VFS.exists(path) then
      resolved = path
      break
    end
  end
  
  if not resolved then
    error("Module introuvable : " .. moduleName .. " (cherché dans : " .. table.concat(searchPaths, ", ") .. ")")
  end
  
  local fn, err = loadfile(resolved, "t", _G)
  if not fn then
    error("Erreur de chargement du module : " .. tostring(err))
  end
  local ok, result = pcall(fn)
  if not ok then
    error("Erreur d'exécution du module : " .. tostring(result))
  end
  return result
end

-- Monkey-patch de l'API fs pour rediriger vers le VFS AdvOS
-- Cette fonction sera appelée après l'initialisation de VFS
local function setupFsRedirect()
  print("Tentative d'activation du monkey-patch fs -> VFS...")
  if VFS and fs then
    print("VFS et fs disponibles, activation du monkey-patch...")
    -- Désactiver temporairement le monkey-patch pour éviter les problèmes
    print("Monkey-patch fs -> VFS désactivé temporairement")
    return
  else
    print("Erreur: VFS ou fs non disponible pour le monkey-patch")
  end
end

-- Appeler le monkey-patch après l'initialisation de VFS
_G.setupFsRedirect = setupFsRedirect

-- API globale vfs (accès direct au VFS AdvOS)
_G.vfs = VFS

-- advos.fs - Système de fichiers VFS
advos.fs = advos.fs or {}
function advos.fs.exists(path)
  return VFS.exists(resolvePath(path))
end

function advos.fs.isDir(path)
  local node = VFS.getNode(resolvePath(path))
  return node and node.type == "directory"
end

function advos.fs.list(path)
  return VFS.list(resolvePath(path))
end

function advos.fs.makeDir(path)
  return VFS.makeDir(resolvePath(path))
end

function advos.fs.delete(path)
  return VFS.delete(resolvePath(path))
end

function advos.fs.copy(from, to)
  local content = VFS.readFile(resolvePath(from))
  if content then
    return VFS.writeFile(resolvePath(to), content)
  end
  return false
end

function advos.fs.move(from, to)
  local content = VFS.readFile(resolvePath(from))
  if content then
    if VFS.writeFile(resolvePath(to), content) then
      return VFS.delete(resolvePath(from))
    end
  end
  return false
end

function advos.fs.open(path, mode)
  local resolved = resolvePath(path)
  if mode == "r" then
    local content = VFS.readFile(resolved)
    if content then
      -- Créer un fichier temporaire pour l'API fs
      local tempFile = "/.AdvOS/temp/fs_temp"
      local file = fs.open(tempFile, "w")
      file.write(content)
      file.close()
      return fs.open(tempFile, mode)
    end
  elseif mode == "w" or mode == "a" then
    -- Wrapper pour rediriger les écritures vers le VFS
    local tempFile = "/.AdvOS/temp/fs_write_temp"
    local file = fs.open(tempFile, mode)
    if file then
      -- Wrapper pour sauvegarder dans le VFS à la fermeture
      local originalClose = file.close
      file.close = function()
        local content = fs.open(tempFile, "r").readAll()
        fs.delete(tempFile)
        VFS.writeFile(resolved, content)
        return originalClose()
      end
      return file
    end
  end
  return nil
end

-- advos.term - Terminal amélioré
advos.term = advos.term or {}
function advos.term.clear()
  term.clear()
  term.setCursorPos(1, 1)
end

function advos.term.write(text)
  term.write(text)
end

function advos.term.print(text)
  print(text)
end

function advos.term.read()
  return read()
end

function advos.term.getCursorPos()
  return term.getCursorPos()
end

function advos.term.setCursorPos(x, y)
  term.setCursorPos(x, y)
end

function advos.term.setTextColor(color)
  term.setTextColor(color)
end

function advos.term.setBackgroundColor(color)
  term.setBackgroundColor(color)
end

-- advos.os - Système d'exploitation
advos.os = advos.os or {}
function advos.os.sleep(time)
  os.sleep(time)
end

function advos.os.time()
  return os.time()
end

function advos.os.date(format)
  return os.date(format)
end

function advos.os.epoch(utc)
  return os.epoch(utc)
end

-- advos.text - Utilitaires de texte
advos.text = advos.text or {}
function advos.text.serialize(data)
  return textutils.serialize(data)
end

function advos.text.unserialize(data)
  return textutils.unserialize(data)
end

function advos.text.formatTime(time)
  return textutils.formatTime(time)
end

-- advos.http - Requêtes HTTP (si disponible)
advos.http = advos.http or {}
if http then
  function advos.http.get(url)
    return http.get(url)
  end
  
  function advos.http.post(url, data)
    return http.post(url, data)
  end
end

-- advos.rednet - Réseau (si disponible)
advos.rednet = advos.rednet or {}
if rednet then
  function advos.rednet.open(side)
    return rednet.open(side)
  end
  
  function advos.rednet.send(id, message)
    return rednet.send(id, message)
  end
  
  function advos.rednet.receive(timeout)
    return rednet.receive(timeout)
  end
end

-- advos.peripheral - Périphériques (si disponible)
advos.peripheral = advos.peripheral or {}
if peripheral then
  function advos.peripheral.find(type)
    return peripheral.find(type)
  end
  
  function advos.peripheral.wrap(name)
    return peripheral.wrap(name)
  end
  
  function advos.peripheral.getNames()
    return peripheral.getNames()
  end
end

-- advos.settings - Paramètres
advos.settings = advos.settings or {}
function advos.settings.set(key, value)
  settings.set(key, value)
end

function advos.settings.get(key, default)
  return settings.get(key, default)
end

function advos.settings.save()
  settings.save()
end

function advos.settings.load()
  settings.load()
end

-- advos.keys - Touches du clavier
advos.keys = advos.keys or {}
for k, v in pairs(keys) do
  advos.keys[k] = v
end

-- advos.colors - Couleurs
advos.colors = advos.colors or {}
for k, v in pairs(colors) do
  advos.colors[k] = v
end

-- advos.requireVFS - Chargement de modules VFS
function advos.requireVFS(modulePath)
  local resolved = resolvePath(modulePath)
  if not VFS.exists(resolved) then
    error("Module introuvable dans le VFS : " .. resolved)
  end
  local fn, err = loadfile(resolved, "t", _G)
  if not fn then
    error("Erreur de chargement du module : " .. tostring(err))
  end
  local ok, result = pcall(fn)
  if not ok then
    error("Erreur d'exécution du module : " .. tostring(result))
  end
  return result
end

-- advos.debug - Mode debug
advos.debug = advos.debug or {}
function advos.debug.isEnabled()
  return _G.DEBUG == true
end

function advos.debug.enable()
  _G.DEBUG = true
end

function advos.debug.disable()
  _G.DEBUG = false
end

function advos.debug.log(message)
  if advos.debug.isEnabled() then
    print("[DEBUG] " .. tostring(message))
  end
end

-- Variables globales

-- Correction : s'assurer que la table 'keys' existe et que 'keys.tab' est défini
if not keys and _G.keys then
    keys = _G.keys
end
if not keys then
    keys = {
        enter = 28,
        backspace = 14,
        delete = 211,
        left = 203,
        right = 205,
        up = 200,
        down = 208,
        tab = 15,
        v = 86,
        c = 67
    }
end

currentPath = "/"
_G.ShellHistory = {
    file = "/.AdvOS/history",
    maxSize = 100,
    entries = {},
    
    load = function()
        if VFS.exists(ShellHistory.file) then
            local content = VFS.readFile(ShellHistory.file)
            if content then
                ShellHistory.entries = textutils.unserialize(content) or {}
            end
        end
    end,
    
    save = function()
        VFS.writeFile(ShellHistory.file, textutils.serialize(ShellHistory.entries))
    end,
    
    add = function(command)
        if #ShellHistory.entries > 0 and ShellHistory.entries[#ShellHistory.entries] == command then
            return
        end
        
        table.insert(ShellHistory.entries, command)
        while #ShellHistory.entries > ShellHistory.maxSize do
            table.remove(ShellHistory.entries, 1)
        end
        
        ShellHistory.save()
    end,
    
    get = function(index)
        if index > 0 and index <= #ShellHistory.entries then
            return ShellHistory.entries[index]
        end
        return nil
    end,
    
    size = function()
        return #ShellHistory.entries
    end
}
local history = {}
local aliases = {}
local envVars = {}
local crashCount = 0
local safeMode = false





-- Fonction de debug
function debug(msg)
    if _G.DEBUG then
        term.setTextColor(colors.orange)
        print("[DEBUG] " .. tostring(msg))
                term.setTextColor(colors.white)
    end
end

-- Fonction de résolution de chemin
function resolvePath(path)
    debug("Resolving path: " .. tostring(path))
    if not path then return currentPath end
    
    -- Chemin absolu
    if path:sub(1,1) == "/" then
        return path
    end
    
    -- Chemin relatif
    local segments = {}
    
    -- Ajouter les segments du chemin courant
    if currentPath ~= "/" then
        for segment in currentPath:gmatch("[^/]+") do
            table.insert(segments, segment)
        end
    end
    
    -- Traiter le chemin relatif
    for segment in path:gmatch("[^/]+") do
        if segment == ".." then
            -- Remonter d'un niveau
            if #segments > 0 then
                table.remove(segments)
            end
        elseif segment ~= "." then
            -- Ajouter le segment
            table.insert(segments, segment)
        end
    end
    
    -- Reconstruire le chemin
    if #segments == 0 then
        return "/"
    else
        return "/" .. table.concat(segments, "/")
    end
end

-- Système de fichiers virtuel
VFS = {
    data = {
        ["/"] = {
            type = "directory",
            content = {},
            created = os.time() or 0,
            modified = os.time() or 0
        }
    },
    
    init = function()
        -- Charger le VFS depuis le fichier
        local file = fs.open("/.AdvOS/vfs.dat", "r")
        if file then
            local data = file.readAll()
            file.close()
            
            local success, loadedData = pcall(textutils.unserialize, data)
            if success and loadedData then
                VFS.data = loadedData
                debug("VFS chargé avec succès")
            else
                debug("Erreur de chargement du VFS, création d'un nouveau")
                VFS.data = {
                    ["/"] = {
                        type = "directory",
                        content = {},
                        created = os.time() or 0,
                        modified = os.time() or 0
                    }
                }
            end
        end
        
        -- Créer les dossiers système s'ils n'existent pas
        local systemDirs = {
            "/.AdvOS",
            "/.AdvOS/apps",
            "/.AdvOS/system",
            "/.AdvOS/temp",
            "/home",
            "/bin",
            "/etc"
        }
        
        for _, dir in ipairs(systemDirs) do
            if not VFS.exists(dir) then
                VFS.makeDir(dir)
    end
end
    end,
    
    save = function()
        -- Sauvegarder le VFS dans le fichier
        local data = textutils.serialize(VFS.data)
        local file = fs.open("/.AdvOS/vfs.dat", "w")
    if file then
            file.write(data)
        file.close()
            debug("VFS sauvegardé avec succès")
            return true
        end
        return false
    end,
    
    getNode = function(path)
        debug("Getting node: " .. path)
        if path == "/" then
            return VFS.data["/"]
        end
        
        local parts = {}
        for part in path:gmatch("[^/]+") do
            table.insert(parts, part)
        end
        
        local current = VFS.data["/"]
        for _, part in ipairs(parts) do
            if not current or current.type ~= "directory" then
                return nil
            end
            current = current.content[part]
        end
        
        return current
    end,
    
    makeDir = function(path)
        debug("Making directory: " .. path)
        if VFS.exists(path) then
            return false, "Path already exists"
        end
        
        local parent = VFS.getParentPath(path)
        local name = VFS.getBaseName(path)
        local parentNode = VFS.getNode(parent)
        
        if not parentNode or parentNode.type ~= "directory" then
            return false, "Parent directory not found"
        end
        
        parentNode.content[name] = {
            type = "directory",
            content = {},
            created = os.time(),
            modified = os.time()
        }
        
        VFS.save()
        return true
    end,
    
    writeFile = function(path, content)
        debug("Writing file: " .. path)
        local parent = VFS.getParentPath(path)
        local name = VFS.getBaseName(path)
        local parentNode = VFS.getNode(parent)
        
        if not parentNode or parentNode.type ~= "directory" then
            return false, "Parent directory not found"
        end
        
        parentNode.content[name] = {
            type = "file",
            content = content,
            created = os.time(),
            modified = os.time()
        }
        
        VFS.save()
        return true
    end,
    
    readFile = function(path)
        local node = VFS.getNode(path)
        if not node or node.type ~= "file" then
            return nil, "File not found"
        end
        return node.content
    end,
    
    exists = function(path)
        return VFS.getNode(path) ~= nil
    end,
    
    list = function(path)
        local node = VFS.getNode(path)
        if not node or node.type ~= "directory" then
            return nil, "Directory not found"
        end
        
        local files = {}
        for name, _ in pairs(node.content) do
            table.insert(files, name)
        end
        table.sort(files)
        return files
    end,
    
    delete = function(path)
        if path == "/" then
            return false, "Cannot delete root"
        end
        
        local parent = VFS.getParentPath(path)
        local name = VFS.getBaseName(path)
        local parentNode = VFS.getNode(parent)
        
        if not parentNode or parentNode.type ~= "directory" then
            return false, "Parent directory not found"
        end
        
        if not parentNode.content[name] then
            return false, "Path not found"
        end
        
        parentNode.content[name] = nil
            VFS.save()
        return true
    end,
    
    getParentPath = function(path)
        return path:match("(.+)/[^/]+$") or "/"
    end,
    
    getBaseName = function(path)
        return path:match("[^/]+$")
    end,
    
    getInfo = function(path)
        local node = VFS.getNode(path)
        if not node then
            return nil, "Path not found"
        end
        
        return {
            type = node.type,
            created = node.created,
            modified = node.modified,
            size = node.type == "file" and #(node.content or "") or nil
        }
    end,
    
    combine = function(path1, path2)
        return VFS.combine(path1, path2)
    end
}

-- Système de gestion des paquets avec compression
_G.AppSystem = {
    REPO_URL = "https://raw.githubusercontent.com/kizYTB/CC-pkg/refs/heads/main/packages.json",
    APPS_DIR = "/.AdvOS/apps",
    TEMP_DIR = "/.AdvOS/temp",
    
    -- Décompresse une archive .advp
    extractPackage = function(archivePath, targetDir)
        debug("Extracting package: " .. archivePath)
        
        -- Lire l'archive
        local file = fs.open(archivePath, "rb")
        if not file then
            return false, "Impossible de lire l'archive"
        end
        
        local content = file.readAll()
        file.close()
        
        -- Décompresser l'archive
        local decompressed = Compression.decompress(content)
        local success, archive = pcall(textutils.unserialize, decompressed)
        
        if not success or not archive.files then
            return false, "Archive corrompue"
        end
        
        -- Extraire les fichiers
        for path, info in pairs(archive.files) do
            local fullPath = fs.combine(targetDir, path)
            local dir = fs.getDir(fullPath)
            
            if not VFS.exists(dir) then
                VFS.makeDir(dir)
            end
            
            if info.type == "file" then
                VFS.writeFile(fullPath, info.content)
            end
        end
        
        return true
    end,
    
    -- Crée une archive .advp
    createPackage = function(sourceDir, targetFile)
        debug("Creating package from: " .. sourceDir)
        
        local archive = {
            files = {},
            metadata = {
                created = os.epoch("local"),
                format = "ADVP",
                version = "1.0"
            }
        }
        
        -- Fonction récursive pour ajouter les fichiers
        local function addDir(dir)
            local files = VFS.list(dir)
            for _, file in ipairs(files) do
                local path = fs.combine(dir, file)
                local info = VFS.getInfo(path)
                
                if info.type == "file" then
                    archive.files[path] = {
                        type = "file",
                        content = VFS.readFile(path),
                        modified = info.modified
                    }
                elseif info.type == "directory" then
                    addDir(path)
                end
            end
        end
        
        addDir(sourceDir)
        
        -- Compresser l'archive
        local serialized = textutils.serialize(archive)
        local compressed = Compression.compress(serialized)
        
        -- Sauvegarder l'archive
        local file = fs.open(targetFile, "wb")
        if not file then
            return false, "Impossible de créer l'archive"
        end
        
        file.write(compressed)
            file.close()
        
        return true
    end,
    
    SYSTEM_VERSION = "1.0.0",
    
    checkCompatibility = function(package)
        if not package.compatibility then
            return true
        end
        
        -- Vérifier la version minimale requise
        if package.compatibility.minVersion then
            local current = _G.AppSystem.parseVersion(_G.AppSystem.SYSTEM_VERSION)
            local required = _G.AppSystem.parseVersion(package.compatibility.minVersion)
            
            if not _G.AppSystem.isVersionGreaterOrEqual(current, required) then
                return false, "Nécessite AdvOS " .. package.compatibility.minVersion .. " ou supérieur"
            end
        end
        
        -- Vérifier les conflits
        if package.compatibility.conflicts then
            for _, conflict in ipairs(package.compatibility.conflicts) do
                if VFS.exists(_G.AppSystem.APPS_DIR .. "/" .. conflict) then
                    return false, "Conflit avec le paquet " .. conflict
                end
            end
        end
        
        -- Vérifier l'architecture ou autres contraintes
        if package.compatibility.requires then
            for requirement, value in pairs(package.compatibility.requires) do
                -- Ajouter ici d'autres vérifications selon les besoins
                if requirement == "os" and value ~= "AdvOS" then
                    return false, "Nécessite " .. value
                end
            end
        end
        
            return true
    end,
    
    parseVersion = function(version)
        local major, minor, patch = version:match("(%d+)%.(%d+)%.(%d+)")
        return {
            major = tonumber(major) or 0,
            minor = tonumber(minor) or 0,
            patch = tonumber(patch) or 0
        }
    end,
    
    isVersionGreaterOrEqual = function(v1, v2)
        if v1.major > v2.major then return true end
        if v1.major < v2.major then return false end
        if v1.minor > v2.minor then return true end
        if v1.minor < v2.minor then return false end
        return v1.patch >= v2.patch
    end,
    
    checkUpdates = function()
        debug("Checking for updates...")
        local packages = _G.AppSystem.fetchPackageList()
        if not packages then
            return false, "Impossible de vérifier les mises à jour"
        end
        
        local updates = {}
        local systemUpdate = nil
        
        -- Parcourir les paquets installés
        local files = VFS.list(_G.AppSystem.APPS_DIR)
        for _, name in ipairs(files) do
            local metadata = VFS.readFile(_G.AppSystem.APPS_DIR .. "/" .. name .. "/app.adv")
            if metadata then
                metadata = textutils.unserialize(metadata)
                local remotePackage = packages.packages[name]
                
                if remotePackage and remotePackage.version then
                    local currentVersion = _G.AppSystem.parseVersion(metadata.version)
                    local remoteVersion = _G.AppSystem.parseVersion(remotePackage.version)
                    
                    if not _G.AppSystem.isVersionGreaterOrEqual(currentVersion, remoteVersion) then
                        if name == "advos" then
                            systemUpdate = {
                                name = name,
                                currentVersion = metadata.version,
                                newVersion = remotePackage.version
                            }
                        else
                            table.insert(updates, {
                                name = name,
                                currentVersion = metadata.version,
                                newVersion = remotePackage.version
                            })
                        end
                    end
                end
            end
        end
        
        return updates, systemUpdate
    end,
    
    update = function(packageName)
        if packageName == "advos" then
            return false, "Utilisez 'pkg system-update' pour mettre à jour AdvOS"
        end
        
        debug("Updating package: " .. packageName)
        
        -- Vérifier si le paquet est installé
        if not VFS.exists(_G.AppSystem.APPS_DIR .. "/" .. packageName) then
            return false, "Le paquet n'est pas installé"
        end
        
        -- Récupérer les informations du paquet
        local packages = _G.AppSystem.fetchPackageList()
        if not packages then
            return false, "Impossible de récupérer les informations de mise à jour"
        end
        
        local package = packages.packages[packageName]
        if not package then
            return false, "Paquet non trouvé dans le dépôt"
        end
        
        -- Vérifier la compatibilité
        local compatible, reason = _G.AppSystem.checkCompatibility(package)
        if not compatible then
            return false, "Incompatible: " .. reason
        end
        
        -- Sauvegarder les données utilisateur si nécessaire
        local userData = {}
        if package.preserveData then
            for _, file in ipairs(package.preserveData) do
                local data = VFS.readFile(_G.AppSystem.APPS_DIR .. "/" .. packageName .. "/" .. file)
                if data then
                    userData[file] = data
                end
            end
        end
        
        -- Désinstaller l'ancienne version
        VFS.delete(_G.AppSystem.APPS_DIR .. "/" .. packageName)
        
        -- Installer la nouvelle version
        local success, err = _G.AppSystem.installPackage(packageName)
        if not success then
            return false, "Erreur de mise à jour: " .. (err or "")
        end
        
        -- Restaurer les données utilisateur
        if package.preserveData then
            for file, data in pairs(userData) do
                VFS.writeFile(_G.AppSystem.APPS_DIR .. "/" .. packageName .. "/" .. file, data)
            end
        end
        
        return true
    end,
    
    systemUpdate = function()
        debug("Checking for system update...")
        
        local packages = _G.AppSystem.fetchPackageList()
        if not packages or not packages.packages.advos then
            return false, "Impossible de vérifier la mise à jour système"
        end
        
        local systemPackage = packages.packages.advos
        local currentVersion = _G.AppSystem.parseVersion(_G.AppSystem.SYSTEM_VERSION)
        local newVersion = _G.AppSystem.parseVersion(systemPackage.version)
        
        if _G.AppSystem.isVersionGreaterOrEqual(currentVersion, newVersion) then
            return false, "Le système est à jour"
        end
        
        print("Mise à jour système disponible: " .. systemPackage.version)
        print("Cette opération va redémarrer le système.")
        write("Voulez-vous continuer? (o/n): ")
        local response = read():lower()
        
        if response ~= "o" and response ~= "oui" then
            return false, "Mise à jour annulée"
        end
        
        -- Sauvegarder les données importantes
        print("Sauvegarde des données...")
        local backup = {
            vfs = VFS.data,
            apps = {}
        }
        
        local files = VFS.list(_G.AppSystem.APPS_DIR)
        for _, name in ipairs(files) do
            if name ~= "advos" then
                local metadata = VFS.readFile(_G.AppSystem.APPS_DIR .. "/" .. name .. "/app.adv")
                if metadata then
                    backup.apps[name] = textutils.unserialize(metadata)
                end
            end
        end
        
        -- Installer la mise à jour
        print("Installation de la mise à jour...")
        local success, err = pcall(function()
            local fn = loadstring(systemPackage.install)
            setfenv(fn, getfenv())
            fn()
        end)
        
        if not success then
            return false, "Erreur de mise à jour: " .. tostring(err)
        end
        
        -- Restaurer les données
        print("Restauration des données...")
        VFS.data = backup.vfs
        
        -- Mettre à jour la version
        _G.AppSystem.SYSTEM_VERSION = systemPackage.version
        
        print("Mise à jour terminée. Redémarrage...")
        os.sleep(2)
        os.reboot()
        
        return true
    end,
    
    fetchPackageList = function()
        debug("Fetching package list from repository")
        local response = http.get(_G.AppSystem.REPO_URL)
        if not response then
            return nil, "Impossible de récupérer la liste des paquets"
        end
        local data = response.readAll()
        response.close()
        
        local ok, result = pcall(textutils.unserializeJSON, data)
        if not ok then
            return nil, "Erreur de lecture du fichier JSON"
        end
        return result
    end,
    
    installPackage = function(packageName, installed)
        installed = installed or {}
        debug("Installing package: " .. packageName)
        
        -- Vérifier si le paquet est déjà installé
        if VFS.exists(fs.combine(AppSystem.APPS_DIR, packageName)) then
            if not installed[packageName] then
                print("Le paquet " .. packageName .. " est déjà installé")
            end
            return true
        end
        
        -- Récupérer les informations du paquet
        local packages = AppSystem.fetchPackageList()
        if not packages then
            return false, "Impossible de récupérer la liste des paquets"
        end
        
        local package = packages.packages[packageName]
        if not package then
            return false, "Paquet introuvable: " .. packageName
        end
        
        -- Installer les dépendances
        if package.dependencies then
            for _, dependency in ipairs(package.dependencies) do
                print("Installation de la dépendance: " .. dependency)
                local success, err = AppSystem.installPackage(dependency, installed)
                if not success then
                    return false, "Erreur d'installation de la dépendance " .. dependency .. ": " .. (err or "")
                end
            end
        end
        
        -- Créer le dossier temporaire
        local tempDir = fs.combine(AppSystem.TEMP_DIR, packageName)
        VFS.makeDir(tempDir)
        
        -- Télécharger l'archive .advp
        print("Téléchargement de " .. packageName .. "...")
        local response = http.get(package.download)
        if not response then
            VFS.delete(tempDir)
            return false, "Impossible de télécharger le paquet"
        end
        
        local archivePath = fs.combine(tempDir, packageName .. ".advp")
        local file = fs.open(archivePath, "wb")
        file.write(response.readAll())
            file.close()
        response.close()
        
        -- Extraire l'archive
        print("Extraction de l'archive...")
        local success, err = AppSystem.extractPackage(archivePath, fs.combine(AppSystem.APPS_DIR, packageName))
        VFS.delete(tempDir)
        
        if not success then
            return false, err
        end
        
        -- Enregistrer les commandes de l'application
        local appInfo = VFS.readFile(fs.combine(AppSystem.APPS_DIR, packageName, "app.adv"))
        if appInfo then
            appInfo = textutils.unserialize(appInfo)
            if appInfo.commands then
                for cmdName, cmdInfo in pairs(appInfo.commands) do
                    -- Créer une fonction wrapper pour la commande
                    local wrapper = function(args)
                        return AppSystem.runAppCommand(packageName, cmdName, args)
                    end
                    
                    -- Enregistrer la commande
                    commandSystem.register(cmdName, {
                        exec = wrapper,
                        desc = cmdInfo.description or "Commande de " .. packageName,
                        type = "app",
                        app = packageName
                    })
                end
            end
        end
        
        installed[packageName] = true
        print(packageName .. " installé avec succès")
        return true
    end,
    
    uninstallPackage = function(packageName)
        debug("Uninstalling package: " .. packageName)
        
        local appDir = fs.combine(AppSystem.APPS_DIR, packageName)
        if not VFS.exists(appDir) then
            return false, "Le paquet n'est pas installé"
        end
        
        -- Lire les métadonnées
        local appInfo = VFS.readFile(fs.combine(appDir, "app.adv"))
        if appInfo then
            appInfo = textutils.unserialize(appInfo)
            
            -- Supprimer les commandes de l'application
            if appInfo.commands then
                for cmdName, _ in pairs(appInfo.commands) do
                    commandSystem.unregister(cmdName)
                end
            end
            
            -- Vérifier les dépendances inverses
            local packages = AppSystem.fetchPackageList()
            if packages then
                for name, info in pairs(packages.packages) do
                    if info.dependencies then
                        for _, dep in ipairs(info.dependencies) do
                            if dep == packageName and VFS.exists(fs.combine(AppSystem.APPS_DIR, name)) then
                                return false, "Impossible de désinstaller: " .. name .. " dépend de ce paquet"
                            end
                        end
                    end
                end
            end
            
            -- Exécuter le script de désinstallation
            if appInfo.uninstall then
                local env = {
                    VFS = VFS,
                    path = appDir,
                    APP_DATA = fs.combine(appDir, "data")
                }
                
                pcall(function()
                    local fn = loadstring(appInfo.uninstall)
                    setfenv(fn, env)
                    fn()
                end)
            end
        end
        
        -- Supprimer le dossier de l'application
        VFS.delete(appDir)
        print(packageName .. " désinstallé avec succès")
        return true
    end,
    
    runAppCommand = function(appName, cmdName, args)
        local appDir = fs.combine(AppSystem.APPS_DIR, appName)
        local appInfo = VFS.readFile(fs.combine(appDir, "app.adv"))
        
        if not appInfo then
            return false, "Application non trouvée"
        end
        
        appInfo = textutils.unserialize(appInfo)
        if not appInfo.commands or not appInfo.commands[cmdName] then
            return false, "Commande non trouvée"
        end
        
        local cmdInfo = appInfo.commands[cmdName]
        local env = {
            VFS = VFS,
            path = appDir,
            APP_DATA = fs.combine(appDir, "data"),
            args = args
        }
        
        local success, err = pcall(function()
            local fn = loadstring(cmdInfo.code)
            setfenv(fn, env)
            return fn()
        end)
        
        if not success then
            return false, "Erreur d'exécution: " .. tostring(err)
        end
        
        return true
    end
}

-- Système de gestion des applications
_G.AppManager = {
    APPS_DIR = "/.AdvOS/apps",
    
    -- Charge les informations d'une application
    loadAppInfo = function(appName)
        local appDir = fs.combine(AppManager.APPS_DIR, appName)
        local infoFile = fs.combine(appDir, "app.adv")
        
        if not VFS.exists(infoFile) then
            return nil, "Application non trouvée"
        end
        
        local content = VFS.readFile(infoFile)
        if not content then
            return nil, "Impossible de lire les informations de l'application"
        end
        
        local success, info = pcall(textutils.unserialize, content)
        if not success or not info then
            return nil, "Format d'information invalide"
        end
        
        return info
    end,
    
    -- Crée une nouvelle application
    createApp = function(appName, info)
        if not appName:match("^[%w_-]+$") then
            return false, "Nom d'application invalide (utilisez uniquement lettres, chiffres, - et _)"
        end
        
        local appDir = fs.combine(AppManager.APPS_DIR, appName)
        if VFS.exists(appDir) then
            return false, "Une application avec ce nom existe déjà"
        end
        
        -- Créer la structure de dossiers
        VFS.makeDir(appDir)
        VFS.makeDir(fs.combine(appDir, appName))
        
        -- Créer le fichier app.adv avec les métadonnées
        local metadata = {
            name = info.name or appName,
            version = info.version or "1.0.0",
            author = info.author or "Unknown",
            description = info.description or "",
            category = info.category or "misc",
            created = os.epoch("local"),
            modified = os.epoch("local"),
            permissions = info.permissions or {
                fs = "app",      -- app, home, system
                net = false,     -- true/false
                term = "full",   -- none, basic, full
                env = "sandbox"  -- none, sandbox, full
            },
            dependencies = info.dependencies or {},
            settings = info.settings or {}
        }
        
        VFS.writeFile(fs.combine(appDir, "app.adv"), textutils.serialize(metadata))
        
        -- Créer le lanceur app.lua
        local launcher = [[
-- Lanceur pour ]] .. appName .. [[

local function main()
    -- Charger les métadonnées
    local info = AppManager.loadAppInfo("]] .. appName .. [[")
    if not info then
        error("Impossible de charger l'application")
    end
    
    -- Configurer l'environnement
    local env = {}
    if info.permissions.env == "sandbox" then
        -- Environnement restreint
        env = {
            term = term,
            write = write,
            print = print,
            read = read,
            os = {
                time = os.time,
                date = os.date,
                epoch = os.epoch,
                sleep = os.sleep
            }
        }
    elseif info.permissions.env == "full" then
        -- Environnement complet
        env = _G
    end
    
    -- Ajouter les APIs spécifiques
    env.APP_INFO = info
    env.APP_PATH = "/.AdvOS/apps/]] .. appName .. [[/]] .. appName .. [["
    env.APP_DATA = "/.AdvOS/apps/]] .. appName .. [[/data"
    
    -- Créer le dossier de données si nécessaire
    if not VFS.exists(env.APP_DATA) then
        VFS.makeDir(env.APP_DATA)
    end
    
    -- Charger et exécuter l'application
    local mainFile = fs.combine(env.APP_PATH, "main.lua")
    local content = VFS.readFile(mainFile)
    if not content then
        error("Impossible de charger le fichier principal")
    end
    
    local fn, err = load(content, "main", "t", env)
    if not fn then
        error("Erreur de syntaxe: " .. (err or ""))
    end
    
    return fn()
end

-- Gestion des erreurs
local ok, err = pcall(main)
if not ok then
            term.setTextColor(colors.red)
    print("Erreur: " .. tostring(err))
            term.setTextColor(colors.white)
        end
]]
        
        VFS.writeFile(fs.combine(appDir, "app.lua"), launcher)
        
        -- Créer le fichier main.lua de base
        local mainCode = [[
-- Application ]] .. name .. [[

-- Récupérer les informations de l'application
local info = APP_INFO
local appPath = APP_PATH
local dataPath = APP_DATA

-- Fonction principale
local function main()
    term.clear()
    term.setCursorPos(1, 1)
    
    -- En-tête
    term.setTextColor(colors.yellow)
    print("=== " .. info.name .. " v" .. info.version .. " ===")
    print(info.description)
    print("Par " .. info.author)
    print(string.rep("=", 40))
    term.setTextColor(colors.white)
    
    -- Code de l'application ici
    print("\nBienvenue dans votre application!")
    
    -- Exemple de sauvegarde
    local data = {
        lastRun = os.epoch("local")
    }
    
    local file = fs.open(fs.combine(APP_DATA, "data.json"), "w")
    file.write(textutils.serializeJSON(data))
    file.close()
end

-- Lancer l'application
main()
]]
        
        VFS.writeFile(fs.combine(appDir, name, "main.lua"), mainCode)
        
        return true
    end,
    
    -- Lance une application
    runApp = function(appName)
        local appDir = fs.combine(AppManager.APPS_DIR, appName)
        local launcherPath = fs.combine(appDir, "app.lua")
        
        if not VFS.exists(launcherPath) then
            return false, "Application non trouvée"
        end
        
        -- Charger et exécuter le lanceur
        local content = VFS.readFile(launcherPath)
        if not content then
            return false, "Impossible de charger le lanceur"
        end
        
        -- Créer l'environnement de l'application
        local env = {
            VFS = VFS,
            term = term,
            colors = colors,
            write = write,
            print = print,
            read = read,
            os = {
                time = os.time,
                date = os.date,
                epoch = os.epoch,
                sleep = os.sleep
            },
            fs = fs,
            textutils = textutils,
            AppManager = AppManager
        }
        
        -- Charger les métadonnées
        local info = AppManager.loadAppInfo(appName)
        if info then
            env.APP_INFO = info
            env.APP_PATH = fs.combine(appDir, appName)
            env.APP_DATA = fs.combine(appDir, "data")
            
            -- Ajouter les permissions selon la configuration
            if info.permissions then
                if info.permissions.net then
                    env.http = http
                end
                if info.permissions.env == "full" then
                    env = _G
                end
            end
        end
        
        -- Exécuter l'application
        local fn, err = load(content, "app:" .. appName, "t", env)
        if not fn then
            return false, "Erreur de syntaxe: " .. (err or "")
        end
        
        local success, result = pcall(fn)
        if not success then
            return false, "Erreur d'exécution: " .. tostring(result)
        end
        
        return true
    end,
    
    -- Liste toutes les applications installées
    listApps = function()
        local apps = {}
        local files = VFS.list(AppManager.APPS_DIR)
        
        for _, name in ipairs(files) do
            local info = AppManager.loadAppInfo(name)
            if info then
                table.insert(apps, {
                    name = name,
                    info = info
                })
            end
        end
        
        return apps
    end,
    
    -- Vérifie si une application existe
    exists = function(appName)
        return VFS.exists(fs.combine(AppManager.APPS_DIR, appName))
    end
}

-- Système de commandes
commandSystem = {
    commands = {},
    commandsDir = "/.sys/commands",
    
    register = function(name, info)
        if type(info) ~= "table" then return false end
        commandSystem.commands[name] = info
        return true
    end,
    
    unregister = function(name)
        commandSystem.commands[name] = nil
        return true
    end,
    
    execute = function(name, args)
        local cmd = commandSystem.commands[name]
        if not cmd then 
            if commands[name] then
                return pcall(commands[name], args)
            end
            return false, "Commande non trouvée"
        end
        
        if cmd.exec then
            return pcall(cmd.exec, args)
        elseif cmd.path then
            return runProgram(cmd.path, args)
        end
    end,
    
    loadCommands = function()
        debug("Loading commands...")
        -- Descriptions des commandes
        local descriptions = {
            help = "Affiche l'aide des commandes",
            clear = "Efface l'écran",
            ls = "Liste le contenu du dossier",
            cd = "Change de dossier",
            mkdir = "Crée un dossier",
            touch = "Crée un fichier",
            cat = "Affiche le contenu d'un fichier",
            rm = "Supprime un fichier ou dossier",
            reboot = "Redémarre le système",
            pkg = "Gestionnaire de paquets",
            exit = "Quitte le mode debug",
            edit = "Édite un fichier avec l'éditeur CraftOS",
            run = "Lance un fichier .adv",
            execute = "Exécute un fichier Lua",
            fs = "Commandes système de fichiers (VFS)",
            advinstall = "Installe AdvOS depuis un fichier .advinstall",
            advbuild = "Crée un fichier .advinstall pour installer AdvOS",
            rednet = "Commandes réseau rednet",
            wget = "Télécharge un fichier depuis Internet",
            wrun = "Télécharge et exécute un programme depuis Internet",
            clipboard = "Gestion du presse-papiers simple",
            import = "Importe un fichier depuis le système hôte vers le VFS (mode debug uniquement)",
            pastebin = "Télécharge un programme depuis Pastebin",
            debug = "Active/désactive le mode debug",
            compress = "Système de compression et décompression de fichiers",
            app = "Gestionnaire d'applications AdvOS",
            bg = "Lance un programme en arrière-plan",
            ps = "Liste les processus en cours",
            kill = "Termine un processus"
        }
        
        -- Charger les commandes de base
        for name, cmd in pairs(commands) do
            commandSystem.register(name, {
                exec = cmd,
                desc = descriptions[name] or "Commande système"
            })
        end
    end,
    
    list = function()
        local result = {}
        for name, info in pairs(commandSystem.commands) do
            table.insert(result, {
                name = name,
                desc = info.desc or "Pas de description",
                type = info.exec and "builtin" or "program"
            })
        end
        return result
    end
}

-- Commandes de base
commands = {
    clear = function()
        term.clear()
        term.setCursorPos(1, 1)
        return true
    end,
    
    help = function(args)
        term.setTextColor(colors.cyan)
        print("AdvOS Shell - Commandes disponibles:")
        print("=================================")
        term.setTextColor(colors.white)
        
        local cmds = commandSystem.list()
        table.sort(cmds, function(a, b) return a.name < b.name end)
        
        for _, cmd in ipairs(cmds) do
            local cmdType = cmd.type == "builtin" and colors.yellow or colors.green
            term.setTextColor(cmdType)
            write(string.format("%-12s", cmd.name))
            term.setTextColor(colors.white)
            print(" - " .. cmd.desc)
        end
        return true
    end,
    
    -- Commandes fs qui écrivent dans le VFS
    fs = function(args)
        if not args[1] then
            print("Usage: fs <command> [args]")
            print("Commands: list, exists, isDir, isReadOnly, getName, getSize, getFreeSpace")
            print("          makeDir, move, copy, delete, open")
            return true
        end
        
        local command = args[1]
        table.remove(args, 1)
        
        if command == "list" then
            local path = args[1] or currentPath
            local files = VFS.list(path)
            if files then
                for _, file in ipairs(files) do
                    print(file)
                end
            else
                print("Directory not found")
            end
            
        elseif command == "exists" then
            local path = args[1]
            if path then
                print(VFS.exists(path))
            else
                print("Usage: fs exists <path>")
            end
            
        elseif command == "isDir" then
            local path = args[1]
            if path then
                local node = VFS.getNode(path)
                print(node and node.type == "directory")
            else
                print("Usage: fs isDir <path>")
            end
            
        elseif command == "makeDir" then
            local path = args[1]
            if path then
                local success = VFS.makeDir(path)
                print(success and "Directory created" or "Failed to create directory")
            else
                print("Usage: fs makeDir <path>")
            end
            
        elseif command == "delete" then
            local path = args[1]
            if path then
                local success = VFS.delete(path)
                print(success and "Deleted" or "Failed to delete")
            else
                print("Usage: fs delete <path>")
            end
            
        elseif command == "open" then
            local path = args[1]
            local mode = args[2] or "r"
            if path then
                local content = VFS.readFile(path)
                if content then
                    -- Créer un fichier temporaire pour l'API fs
                    local tempFile = "/.AdvOS/temp/fs_temp"
                    local file = fs.open(tempFile, "w")
                    file.write(content)
                    file.close()
                    
                    -- Retourner un handle vers le fichier temporaire
                    local handle = fs.open(tempFile, mode)
                    if handle then
                        -- Wrapper pour rediriger les écritures vers le VFS
                        local originalWrite = handle.write
                        handle.write = function(self, data)
                            originalWrite(self, data)
                            -- Sauvegarder dans le VFS quand on ferme
                            local tempContent = fs.open(tempFile, "r")
                            if tempContent then
                                VFS.writeFile(path, tempContent.readAll())
                                tempContent.close()
                            end
                        end
                        return handle
                    end
                else
                    print("File not found")
                end
            else
                print("Usage: fs open <path> [mode]")
            end
            
        else
            print("Unknown fs command: " .. command)
        end
        
        return true
    end,
    
    -- Système d'installation AdvOS
    advinstall = function(args)
        if not args[1] then
            print("Usage: advinstall <file.advinstall>")
            return false
        end
        
        local filePath = args[1]
        local file = fs.open(filePath, "rb")
        if not file then
            print("Fichier .advinstall non trouvé: " .. filePath)
            return false
        end
        
        local content = file.readAll()
        file.close()
        
        -- Décompresser l'archive
        local decompressed = content
        local success, archive = pcall(textutils.unserialize, decompressed)
        
        -- Si c'est un fichier compressé, essayer de le décompresser
        if not success or not archive then
            -- Essayer de décompresser avec le système AdvOS
            local compressorPath = "/.AdvOS/tools/compressor.lua"
            if VFS.exists(compressorPath) then
                local content = VFS.readFile(compressorPath)
                local env = createAdvosEnvironment()
                local fn, err = load(content, "compressor", "t", env)
                
                if fn then
                    local success2, Compressor = pcall(fn)
                    if success2 and Compressor then
                        local success3, compressed = pcall(textutils.unserialize, content)
                        if success3 and compressed then
                            local decompressed = Compressor.decompressAdvanced(compressed)
                            success, archive = pcall(textutils.unserialize, decompressed)
                        end
                    end
                end
            end
        end
        
        if not success or not archive then
            print("Archive .advinstall corrompue")
            return false
        end
        
        print("Installation d'AdvOS...")
        print("Version: " .. (archive.version or "Unknown"))
        print("Fichiers à installer: " .. (archive.fileCount or 0))
        
        -- Installer les fichiers
        local installed = 0
        for path, data in pairs(archive.files) do
            local fullPath = "/" .. path
            local dir = VFS.getParentPath(fullPath)
            
            -- Créer le dossier parent si nécessaire
            if not VFS.exists(dir) then
                VFS.makeDir(dir)
            end
            
            -- Écrire le fichier
            if VFS.writeFile(fullPath, data.content) then
                installed = installed + 1
            end
        end
        
        print("Installation terminée! " .. installed .. " fichiers installés")
        print("Redémarrage dans 3 secondes...")
        os.sleep(3)
        os.reboot()
        
        return true
    end,
    
    -- Créer un fichier .advinstall
    advbuild = function(args)
        if not args[1] then
            print("Usage: advbuild <output.advinstall>")
            return false
        end
        
        local outputFile = args[1]
        print("Création de l'archive AdvOS...")
        
        local archive = {
            version = "1.0.0",
            created = os.epoch("local"),
            fileCount = 0,
            files = {}
        }
        
        -- Fonction récursive pour ajouter les fichiers
        local function addDir(dir)
            local files = VFS.list(dir)
            for _, file in ipairs(files) do
                local path = dir .. "/" .. file
                local info = VFS.getInfo(path)
                
                if info.type == "file" then
                    local content = VFS.readFile(path)
                    if content then
                        archive.files[path:sub(2)] = { -- Enlever le / initial
                            content = content,
                            modified = info.modified
                        }
                        archive.fileCount = archive.fileCount + 1
                    end
                elseif info.type == "directory" then
                    addDir(path)
                end
            end
        end
        
        addDir("/")
        
        -- Compresser l'archive
        local serialized = textutils.serialize(archive)
        
        -- Utiliser le système de compression AdvOS
        local compressorPath = "/.AdvOS/tools/compressor.lua"
        if VFS.exists(compressorPath) then
            local content = VFS.readFile(compressorPath)
            local env = createAdvosEnvironment()
            local fn, err = load(content, "compressor", "t", env)
            
            if fn then
                local success, Compressor = pcall(fn)
                if success and Compressor then
                    local compressed = Compressor.compressAdvanced(serialized, "advz")
                    local compressedData = textutils.serialize(compressed)
                    
                    -- Sauvegarder
                    local file = fs.open(outputFile, "wb")
                    if not file then
                        print("Erreur: Impossible de créer l'archive")
                        return false
                    end
                    
                    file.write(compressedData)
                    file.close()
                    
                    print("Archive créée: " .. outputFile)
                    print("Taille: " .. #compressedData .. " bytes")
                    print("Fichiers inclus: " .. archive.fileCount)
                    
                    return true
                end
            end
        end
        
        -- Fallback: sauvegarder sans compression
        local file = fs.open(outputFile, "wb")
        if not file then
            print("Erreur: Impossible de créer l'archive")
            return false
        end
        
        file.write(serialized)
        file.close()
        
        print("Archive créée (non compressée): " .. outputFile)
        print("Taille: " .. #serialized .. " bytes")
        print("Fichiers inclus: " .. archive.fileCount)
        
        return true
    end,
    
    -- Rednet
    rednet = function(args)
        if not args[1] then
            print("Usage: rednet <command> [args]")
            print("Commands: open, close, send, broadcast, receive, lookup")
            return true
        end
        
        local command = args[1]
        table.remove(args, 1)
        
        if command == "open" then
            local side = args[1] or "right"
            rednet.open(side)
            print("Rednet ouvert sur " .. side)
            
        elseif command == "close" then
            rednet.close()
            print("Rednet fermé")
            
        elseif command == "send" then
            local id = tonumber(args[1])
            local message = args[2]
            if id and message then
                rednet.send(id, message)
                print("Message envoyé à " .. id)
            else
                print("Usage: rednet send <id> <message>")
            end
            
        elseif command == "broadcast" then
            local message = args[1]
            if message then
                rednet.broadcast(message)
                print("Message diffusé")
            else
                print("Usage: rednet broadcast <message>")
            end
            
        elseif command == "receive" then
            local timeout = tonumber(args[1]) or 5
            print("En attente de message (timeout: " .. timeout .. "s)...")
            local id, message = rednet.receive(timeout)
            if id then
                print("Message reçu de " .. id .. ": " .. message)
            else
                print("Aucun message reçu")
            end
            
        elseif command == "lookup" then
            local protocol = args[1]
            if protocol then
                local hosts = rednet.lookup(protocol)
                if hosts then
                    for _, host in ipairs(hosts) do
                        print("Host: " .. host)
                    end
                else
                    print("Aucun host trouvé pour " .. protocol)
                end
            else
                print("Usage: rednet lookup <protocol>")
            end
            
        else
            print("Commande rednet inconnue: " .. command)
        end
        
        return true
    end,
    
    -- Wget
    wget = function(args)
        if not args[1] then
            print("Usage: wget <url> [filename]")
            return false
        end
        
        local url = args[1]
        local filename = args[2] or url:match("([^/]+)$") or "download"
        
        print("Téléchargement de " .. url)
        local response = http.get(url)
        if not response then
            print("Erreur: Impossible de télécharger")
            return false
        end
        
        local content = response.readAll()
        response.close()
        
        -- Sauvegarder dans le VFS
        local success = VFS.writeFile("/" .. filename, content)
        if success then
            print("Fichier téléchargé: " .. filename)
            print("Taille: " .. #content .. " bytes")
        else
            print("Erreur lors de la sauvegarde")
            return false
        end
        
        return true
    end,
    
    -- Lancer un programme depuis Internet
    wrun = function(args)
        if not args[1] then
            print("Usage: wrun <url>")
            return false
        end
        
        local url = args[1]
        print("Téléchargement et exécution de " .. url)
        
        local response = http.get(url)
        if not response then
            print("Erreur: Impossible de télécharger")
            return false
        end
        
        local content = response.readAll()
        response.close()
        
        -- Exécuter directement avec AdvOS sans fichier temporaire
        print("Exécution avec AdvOS...")
        local success, err = pcall(function()
            -- Créer un environnement AdvOS et charger le code directement
            local env = createAdvosEnvironment()
            local fn, loadErr = load(content, "wrun:" .. url, "t", env)
            if not fn then
                error("Erreur de chargement : " .. loadErr)
            end
            
            local ok, result = pcall(fn)
            if not ok then
                error("Erreur d'exécution : " .. tostring(result))
            end
        end)
        
        if not success then
            print("Erreur d'exécution: " .. tostring(err))
            return false
        end
        
        return true
    end,
    

    
    edit = function(args)
        if not args[1] then
            print("Usage: edit <file>")
            return false
        end
        
        local filePath = resolvePath(args[1])
        
        -- Éditeur intégré directement dans le shell
        local function runEditor()
            -- Get file to edit
            local tArgs = { filePath }
            if #tArgs == 0 then
                print("Usage: edit <path>")
                return
            end
            
            -- Error checking
            local sPath = tArgs[1]
            local bReadOnly = false
            
            -- Vérifier si c'est un dossier
            if VFS.exists(sPath) then
                local node = VFS.getNode(sPath)
                if node and node.type == "directory" then
                    print("Cannot edit a directory.")
                    return
                end
            end
            
            -- Create .lua files by default
            if not VFS.exists(sPath) and not string.find(sPath, "%.") then
                local sExtension = "lua"
                sPath = sPath .. "." .. sExtension
            end
            
            local x, y = 1, 1
            local w, h = term.getSize()
            local scrollX, scrollY = 0, 0
            
            local tLines = {}
            local bRunning = true
            
            -- Colours
            local highlightColour, keywordColour, commentColour, textColour, bgColour, stringColour, errorColour
            if term.isColour() then
                bgColour = colours.black
                textColour = colours.white
                highlightColour = colours.yellow
                keywordColour = colours.yellow
                commentColour = colours.green
                stringColour = colours.red
                errorColour = colours.red
            else
                bgColour = colours.black
                textColour = colours.white
                highlightColour = colours.white
                keywordColour = colours.white
                commentColour = colours.white
                stringColour = colours.white
                errorColour = colours.white
            end
            
            -- Menus
            local bMenu = false
            local nMenuItem = 1
            local tMenuItems = {}
            if not bReadOnly then
                table.insert(tMenuItems, "Save")
            end
            table.insert(tMenuItems, "Exit")
            
            local status_ok, status_text
            local function set_status(text, ok)
                status_ok = ok ~= false
                status_text = text
            end
            
            local message = "Press Ctrl or click here to access menu"
            if #message > w - 5 then
                message = "Press Ctrl for menu"
            end
            set_status(message)
            
            local function load(_sPath)
                tLines = {}
                if VFS.exists(_sPath) then
                    local content = VFS.readFile(_sPath)
                    if content then
                        for line in content:gmatch("[^\r\n]+") do
                            table.insert(tLines, line)
                        end
                    end
                end
                
                if #tLines == 0 then
                    table.insert(tLines, "")
                end
            end
            
            local function save(_sPath, fWrite)
                -- Créer le dossier parent si nécessaire
                local sDir = _sPath:sub(1, _sPath:len() - string.match(_sPath, "[^/]+$"):len())
                if sDir ~= "" and not VFS.exists(sDir) then
                    VFS.makeDir(sDir)
                end
                
                -- Sauvegarder dans le VFS
                local content = ""
                fWrite({ write = function(text) content = content .. text end })
                
                local success = VFS.writeFile(_sPath, content)
                if success then
                    return true, nil, nil
                else
                    return false, "Failed to save to VFS", "VFS write error"
                end
            end
            
            local tKeywords = {
                ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
                ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
                ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
                ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
                ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
                ["while"] = true,
            }
            
            local function tryWrite(sLine, regex, colour)
                local match = string.match(sLine, regex)
                if match then
                    if type(colour) == "number" then
                        term.setTextColour(colour)
                    else
                        term.setTextColour(colour(match))
                    end
                    term.write(match)
                    term.setTextColour(textColour)
                    return string.sub(sLine, #match + 1)
                end
                return nil
            end
            
            local function writeHighlighted(sLine)
                while #sLine > 0 do
                    sLine =
                        tryWrite(sLine, "^%-%-%[%[.-%]%]", commentColour) or
                        tryWrite(sLine, "^%-%-.*", commentColour) or
                        tryWrite(sLine, "^\"\"", stringColour) or
                        tryWrite(sLine, "^\".-[^\\]\"", stringColour) or
                        tryWrite(sLine, "^\'\'", stringColour) or
                        tryWrite(sLine, "^\'.-[^\\]\'", stringColour) or
                        tryWrite(sLine, "^%[%[.-%]%]", stringColour) or
                        tryWrite(sLine, "^[%w_]+", function(match)
                            if tKeywords[match] then
                                return keywordColour
                            end
                            return textColour
                        end) or
                        tryWrite(sLine, "^[^%w_]", textColour)
                end
            end
            
            local function redrawText()
                local cursorX, cursorY = x, y
                for y = 1, h - 1 do
                    term.setCursorPos(1 - scrollX, y)
                    term.clearLine()
                    
                    local sLine = tLines[y + scrollY]
                    if sLine ~= nil then
                        writeHighlighted(sLine)
                    end
                end
                term.setCursorPos(x - scrollX, y - scrollY)
            end
            
            local function redrawLine(_nY)
                local sLine = tLines[_nY]
                if sLine then
                    term.setCursorPos(1 - scrollX, _nY - scrollY)
                    term.clearLine()
                    writeHighlighted(sLine)
                    term.setCursorPos(x - scrollX, _nY - scrollY)
                end
            end
            
            local function redrawMenu()
                -- Clear line
                term.setCursorPos(1, h)
                term.clearLine()
                
                -- Draw line numbers
                term.setCursorPos(w - #("Ln " .. y) + 1, h)
                term.setTextColour(highlightColour)
                term.write("Ln ")
                term.setTextColour(textColour)
                term.write(y)
                
                term.setCursorPos(1, h)
                if bMenu then
                    -- Draw menu
                    term.setTextColour(textColour)
                    for nItem, sItem in pairs(tMenuItems) do
                        if nItem == nMenuItem then
                            term.setTextColour(highlightColour)
                            term.write("[")
                            term.setTextColour(textColour)
                            term.write(sItem)
                            term.setTextColour(highlightColour)
                            term.write("]")
                            term.setTextColour(textColour)
                        else
                            term.write(" " .. sItem .. " ")
                        end
                    end
                else
                    -- Draw status
                    term.setTextColour(status_ok and highlightColour or errorColour)
                    term.write(status_text)
                    term.setTextColour(textColour)
                end
                
                -- Reset cursor
                term.setCursorPos(x - scrollX, y - scrollY)
            end
            
            local tMenuFuncs = {
                Save = function()
                    if bReadOnly then
                        set_status("Access denied", false)
                    else
                        local ok, _, fileerr = save(sPath, function(file)
                            for _, sLine in ipairs(tLines) do
                                file.write(sLine .. "\n")
                            end
                        end)
                        if ok then
                            set_status("Saved to " .. sPath)
                        else
                            if fileerr then
                                set_status("Error saving: " .. fileerr, false)
                            else
                                set_status("Error saving to " .. sPath, false)
                            end
                        end
                    end
                    redrawMenu()
                end,
                Exit = function()
                    bRunning = false
                end,
            }
            
            local function doMenuItem(_n)
                tMenuFuncs[tMenuItems[_n]]()
                if bMenu then
                    bMenu = false
                    term.setCursorBlink(true)
                end
                redrawMenu()
            end
            
            local function setCursor(newX, newY)
                local _, oldY = x, y
                x, y = newX, newY
                local screenX = x - scrollX
                local screenY = y - scrollY
                
                local bRedraw = false
                if screenX < 1 then
                    scrollX = x - 1
                    screenX = 1
                    bRedraw = true
                elseif screenX > w then
                    scrollX = x - w
                    screenX = w
                    bRedraw = true
                end
                
                if screenY < 1 then
                    scrollY = y - 1
                    screenY = 1
                    bRedraw = true
                elseif screenY > h - 1 then
                    scrollY = y - (h - 1)
                    screenY = h - 1
                    bRedraw = true
                end
                
                if bRedraw then
                    redrawText()
                elseif y ~= oldY then
                    redrawLine(oldY)
                    redrawLine(y)
                else
                    redrawLine(y)
                end
                term.setCursorPos(screenX, screenY)
                
                redrawMenu()
            end
            
            -- Actual program functionality begins
            load(sPath)
            
            term.setBackgroundColour(bgColour)
            term.clear()
            term.setCursorPos(x, y)
            term.setCursorBlink(true)
            
            redrawText()
            redrawMenu()
            
            -- Handle input
            while bRunning do
                local sEvent, param, param2, param3 = os.pullEvent()
                if sEvent == "key" then
                    if param == keys.up then
                        -- Up
                        if not bMenu and y > 1 then
                            setCursor(
                                math.min(x, #tLines[y - 1] + 1),
                                y - 1
                            )
                        end
                    elseif param == keys.down then
                        -- Down
                        if not bMenu and y < #tLines then
                            setCursor(
                                math.min(x, #tLines[y + 1] + 1),
                                y + 1
                            )
                        end
                    elseif param == keys.tab then
                        -- Tab
                        if not bMenu and not bReadOnly then
                            -- Indent line
                            local sLine = tLines[y]
                            tLines[y] = string.sub(sLine, 1, x - 1) .. "    " .. string.sub(sLine, x)
                            setCursor(x + 4, y)
                        end
                    elseif param == keys.left then
                        -- Left
                        if not bMenu then
                            if x > 1 then
                                setCursor(x - 1, y)
                            elseif x == 1 and y > 1 then
                                setCursor(#tLines[y - 1] + 1, y - 1)
                            end
                        else
                            -- Move menu left
                            nMenuItem = nMenuItem - 1
                            if nMenuItem < 1 then
                                nMenuItem = #tMenuItems
                            end
                            redrawMenu()
                        end
                    elseif param == keys.right then
                        -- Right
                        if not bMenu then
                            local nLimit = #tLines[y] + 1
                            if x < nLimit then
                                setCursor(x + 1, y)
                            elseif x == nLimit and y < #tLines then
                                setCursor(1, y + 1)
                            end
                        else
                            -- Move menu right
                            nMenuItem = nMenuItem + 1
                            if nMenuItem > #tMenuItems then
                                nMenuItem = 1
                            end
                            redrawMenu()
                        end
                    elseif param == keys.delete then
                        -- Delete
                        if not bMenu and not bReadOnly then
                            local nLimit = #tLines[y] + 1
                            if x < nLimit then
                                local sLine = tLines[y]
                                tLines[y] = string.sub(sLine, 1, x - 1) .. string.sub(sLine, x + 1)
                                redrawLine(y)
                            elseif y < #tLines then
                                tLines[y] = tLines[y] .. tLines[y + 1]
                                table.remove(tLines, y + 1)
                                redrawText()
                            end
                        end
                    elseif param == keys.backspace then
                        -- Backspace
                        if not bMenu and not bReadOnly then
                            if x > 1 then
                                -- Remove character
                                local sLine = tLines[y]
                                if x > 4 and string.sub(sLine, x - 4, x - 1) == "    " and not string.sub(sLine, 1, x - 1):find("%S") then
                                    tLines[y] = string.sub(sLine, 1, x - 5) .. string.sub(sLine, x)
                                    setCursor(x - 4, y)
                                else
                                    tLines[y] = string.sub(sLine, 1, x - 2) .. string.sub(sLine, x)
                                    setCursor(x - 1, y)
                                end
                            elseif y > 1 then
                                -- Remove newline
                                local sPrevLen = #tLines[y - 1]
                                tLines[y - 1] = tLines[y - 1] .. tLines[y]
                                table.remove(tLines, y)
                                setCursor(sPrevLen + 1, y - 1)
                                redrawText()
                            end
                        end
                    elseif param == keys.enter or param == keys.numPadEnter then
                        -- Enter/Numpad Enter
                        if not bMenu and not bReadOnly then
                            -- Newline
                            local sLine = tLines[y]
                            local _, spaces = string.find(sLine, "^[ ]+")
                            if not spaces then
                                spaces = 0
                            end
                            tLines[y] = string.sub(sLine, 1, x - 1)
                            table.insert(tLines, y + 1, string.rep(' ', spaces) .. string.sub(sLine, x))
                            setCursor(spaces + 1, y + 1)
                            redrawText()
                        elseif bMenu then
                            -- Menu selection
                            doMenuItem(nMenuItem)
                        end
                    elseif param == keys.leftCtrl or param == keys.rightCtrl then
                        -- Menu toggle
                        bMenu = not bMenu
                        if bMenu then
                            term.setCursorBlink(false)
                        else
                            term.setCursorBlink(true)
                        end
                        redrawMenu()
                    end
                elseif sEvent == "char" then
                    if not bMenu and not bReadOnly then
                        -- Input text
                        local sLine = tLines[y]
                        tLines[y] = string.sub(sLine, 1, x - 1) .. param .. string.sub(sLine, x)
                        setCursor(x + 1, y)
                    elseif bMenu then
                        -- Select menu items
                        for n, sMenuItem in ipairs(tMenuItems) do
                            if string.lower(string.sub(sMenuItem, 1, 1)) == string.lower(param) then
                                doMenuItem(n)
                                break
                            end
                        end
                    end
                elseif sEvent == "paste" then
                    if not bReadOnly then
                        -- Close menu if open
                        if bMenu then
                            bMenu = false
                            term.setCursorBlink(true)
                            redrawMenu()
                        end
                        -- Input text
                        local sLine = tLines[y]
                        tLines[y] = string.sub(sLine, 1, x - 1) .. param .. string.sub(sLine, x)
                        setCursor(x + #param, y)
                    end
                elseif sEvent == "mouse_click" then
                    local cx, cy = param2, param3
                    if not bMenu then
                        if param == 1 then
                            -- Left click
                            if cy < h then
                                local newY = math.min(math.max(scrollY + cy, 1), #tLines)
                                local newX = math.min(math.max(scrollX + cx, 1), #tLines[newY] + 1)
                                setCursor(newX, newY)
                            else
                                bMenu = true
                                redrawMenu()
                            end
                        end
                    else
                        if cy == h then
                            local nMenuPosEnd = 1
                            local nMenuPosStart = 1
                            for n, sMenuItem in ipairs(tMenuItems) do
                                nMenuPosEnd = nMenuPosEnd + #sMenuItem + 1
                                if cx > nMenuPosStart and cx < nMenuPosEnd then
                                    doMenuItem(n)
                                end
                                nMenuPosEnd = nMenuPosEnd + 1
                                nMenuPosStart = nMenuPosEnd
                            end
                        else
                            bMenu = false
                            term.setCursorBlink(true)
                            redrawMenu()
                        end
                    end
                elseif sEvent == "mouse_scroll" then
                    if not bMenu then
                        if param == -1 then
                            -- Scroll up
                            if scrollY > 0 then
                                scrollY = scrollY - 1
                                redrawText()
                            end
                        elseif param == 1 then
                            -- Scroll down
                            local nMaxScroll = #tLines - (h - 1)
                            if scrollY < nMaxScroll then
                                scrollY = scrollY + 1
                                redrawText()
                            end
                        end
                    end
                elseif sEvent == "term_resize" then
                    w, h = term.getSize()
                    setCursor(x, y)
                    redrawMenu()
                    redrawText()
                end
            end
            
            -- Cleanup
            term.clear()
            term.setCursorBlink(false)
            term.setCursorPos(1, 1)
        end
        
        -- Exécuter l'éditeur intégré
        local success, err = pcall(runEditor)
        if not success then
            print("Erreur d'exécution de l'éditeur: " .. tostring(err))
            return false
        end
        
        return true
    end,
    
    run = function(args)
        if not args[1] then
            print("Usage: run <file>")
            return false
        end
        
        local filePath = resolvePath(args[1])
        local content = VFS.readFile(filePath)
        
        if not content then
            print("Fichier non trouvé: " .. filePath)
            return false
        end
        
        -- Exécuter directement avec AdvOS sans fichier temporaire
        print("Exécution de: " .. filePath)
        local success, err = pcall(function()
            -- Créer un environnement AdvOS et charger le code directement
            local env = createAdvosEnvironment()
            local fn, loadErr = load(content, "run:" .. filePath, "t", env)
            if not fn then
                error("Erreur de chargement : " .. loadErr)
            end
            
            -- Récupérer les arguments
            local runArgs = {}
            for i = 2, #args do
                table.insert(runArgs, args[i])
            end
            
            local ok, result = pcall(fn, table.unpack(runArgs))
            if not ok then
                error("Erreur d'exécution : " .. tostring(result))
            end
        end)
        
        if not success then
            print("Erreur d'exécution: " .. tostring(err))
            return false
        end
        
        return true
    end,
    
    execute = function(args)
        if not args[1] then
            print("Usage: execute <file>")
            return false
        end
        
        local filePath = resolvePath(args[1])
        local content = VFS.readFile(filePath)
        
        if not content then
            print("Fichier non trouvé: " .. filePath)
            return false
        end
        
        -- Utiliser l'environnement AdvOS sécurisé
        local env = createAdvosEnvironment()
        
        -- Charger et exécuter le code
        local fn, err = load(content, "execute:" .. filePath, "t", env)
        if not fn then
            print("Erreur de syntaxe: " .. (err or ""))
            return false
        end
        
        local success, result = pcall(fn)
        if not success then
            print("Erreur d'exécution: " .. tostring(result))
            return false
        end
        
        return true
    end,
    
    ls = function(args)
        local path = resolvePath(args[1] or currentPath)
        debug("Listing directory: " .. path)
        
        local files = VFS.list(path)
        if not files then
            term.setTextColor(colors.red)
            print("Directory not found")
            term.setTextColor(colors.white)
            return false
        end
        
        -- Calculer la largeur maximale pour l'alignement
        local maxWidth = 0
        for _, name in ipairs(files) do
            maxWidth = math.max(maxWidth, #name)
        end
        
        -- En-tête
        term.setTextColor(colors.cyan)
        print("Contents of " .. path)
        print(string.rep("=", 50))
        term.setTextColor(colors.yellow)
        print(string.format("%-" .. maxWidth .. "s  %-6s  %-19s  %s", "Name", "Type", "Modified", "Size"))
        print(string.rep("-", 50))
            term.setTextColor(colors.white)
        
        -- Lister les fichiers avec leurs informations
        for _, name in ipairs(files) do
            local fullPath = path == "/" and "/" .. name or path .. "/" .. name
            local node = VFS.getNode(fullPath)
            if node then
                local nodeType = node.type
                local modified = os.date("%Y-%m-%d %H:%M:%S", node.modified)
                local size = nodeType == "file" and #(node.content or "") or "-"
                
                -- Colorer selon le type
                if nodeType == "directory" then
                    term.setTextColor(colors.blue)
                elseif name:match("%.advs$") then
                    term.setTextColor(colors.green)
                elseif name:match("%.lua$") then
                    term.setTextColor(colors.yellow)
                else
            term.setTextColor(colors.white)
        end
                
                print(string.format("%-" .. maxWidth .. "s  %-6s  %-19s  %s", 
                    name, 
                    nodeType, 
                    modified,
                    size))
            end
        end
        
            term.setTextColor(colors.white)
        return true
    end,
    
    cd = function(args)
        local path = resolvePath(args[1] or "/")
        debug("Changing directory to: " .. path)
        
        if VFS.exists(path) then
            currentPath = path
            return true
        end
        return false, "Directory not found"
    end,
    
    mkdir = function(args)
        if not args[1] then return false, "Usage: mkdir <directory>" end
        local path = resolvePath(args[1])
        debug("Creating directory: " .. path)
        return VFS.makeDir(path)
    end,
    
    touch = function(args)
        if not args[1] then return false, "Usage: touch <file>" end
        local path = resolvePath(args[1])
        debug("Creating file: " .. path)
        return VFS.writeFile(path, "")
    end,
    
    cat = function(args)
        if not args[1] then return false, "Usage: cat <file>" end
        local path = resolvePath(args[1])
        debug("Reading file: " .. path)
        local content = VFS.readFile(path)
        if content then
            print(content)
            return true
        end
        return false, "File not found"
    end,
    
    rm = function(args)
        if not args[1] then return false, "Usage: rm <file/directory>" end
        local path = resolvePath(args[1])
        debug("Deleting: " .. path)
        return VFS.delete(path)
    end,
    
    reboot = function()
        os.reboot()
    end,
    
    exit = function()
        if _G.DEBUG then
            print("Exiting debug mode")
            _G.DEBUG = false
            return true
        end
        return false, "Not in debug mode"
    end,
    
    -- Commande import (mode debug uniquement)
    import = function(args)
        -- Vérifier si on est en mode debug
        if not _G.DEBUG then
            print("Erreur : La commande import n'est disponible qu'en mode debug.")
            return false
        end
        
        if not args[1] or not args[2] then
            print("Usage: import <source_path> <destination_path>")
            print("Exemple: import /startup.lua /mon_programme.lua")
            return false
        end
        
        local sourcePath = args[1]
        local destPath = args[2]
        
        -- Vérifier si le fichier source existe sur le système hôte
        if not fs.exists(sourcePath) then
            print("Erreur : Fichier source introuvable : " .. sourcePath)
            return false
        end
        
        -- Lire le contenu du fichier source
        local file = fs.open(sourcePath, "r")
        if not file then
            print("Erreur : Impossible de lire le fichier source")
            return false
        end
        
        local content = file.readAll()
        file.close()
        
        -- Écrire dans le VFS d'AdvOS
        local success = VFS.writeFile(destPath, content)
        if success then
            print("Import réussi : " .. sourcePath .. " -> " .. destPath)
            return true
        else
            print("Erreur : Impossible d'écrire dans le VFS")
            return false
        end
    end,
    
    -- Commande pastebin pour télécharger depuis Pastebin
    pastebin = function(args)
        if not args[1] then
            print("Usage: pastebin <id> [filename]")
            print("Exemple: pastebin abc123 mon_programme.lua")
            return false
        end
        
        local pasteId = args[1]
        local filename = args[2] or pasteId .. ".lua"
        
        print("Téléchargement depuis Pastebin...")
        
        -- Utiliser la fonction pastebin de ComputerCraft
        -- Utiliser shell.run de CraftOS seulement pour pastebin (API externe)
        local success = shell.run("pastebin", "get", pasteId, filename)
        
        if success then
            print("Téléchargement réussi: " .. filename)
            return true
        else
            print("Erreur lors du téléchargement")
            return false
        end
    end,
    
    -- Commande debug pour activer/désactiver le mode debug
    debug = function(args)
        if not args[1] then
            -- Afficher l'état actuel
            if _G.DEBUG then
                print("Mode debug: ACTIVÉ")
            else
                print("Mode debug: DÉSACTIVÉ")
            end
            print("Usage: debug <on|off>")
            print("Exemple: debug on")
            return true
        end
        
        local action = args[1]:lower()
        
        if action == "on" or action == "true" or action == "1" then
            _G.DEBUG = true
            print("Mode debug ACTIVÉ")
            return true
        elseif action == "off" or action == "false" or action == "0" then
            _G.DEBUG = false
            print("Mode debug DÉSACTIVÉ")
            return true
        else
            print("Usage: debug <on|off>")
            print("Exemple: debug on")
            return false
        end
    end,
    
    compress = function(args)
        if not args[1] then
            print("=== Système de compression AdvOS ===")
            print("Usage:")
            print("  compress <input> <output> [format]  - Compresse un fichier")
            print("  decompress <input> <output>         - Décompresse un fichier")
            print("  analyze <file>                      - Analyse un fichier compressé")
            print("  package <input> <output>            - Compresse un paquet AdvOS")
            print("  unpackage <input> <output>         - Décompresse un paquet AdvOS")
            print("  benchmark <file>                    - Teste tous les algorithmes")
            return true
        end
        
        local command = args[1]
        table.remove(args, 1)
        
        -- Charger le système de compression
        local compressorPath = "/.AdvOS/tools/compressor.lua"
        if not VFS.exists(compressorPath) then
            print("Erreur: Système de compression non trouvé")
            return false
        end
        
        local content = VFS.readFile(compressorPath)
        local env = createAdvosEnvironment()
        local fn, err = load(content, "compressor", "t", env)
        
        if not fn then
            print("Erreur de chargement du compresseur: " .. err)
            return false
        end
        
        local success, Compressor = pcall(fn)
        if not success then
            print("Erreur d'exécution du compresseur: " .. tostring(Compressor))
            return false
        end
        
        if command == "compress" then
            if #args < 2 then
                print("Usage: compress compress <input> <output> [format]")
                return false
            end
            local format = args[3] or "advz"
            return Compressor.compressFile(args[1], args[2], format)
            
        elseif command == "decompress" then
            if #args < 2 then
                print("Usage: compress decompress <input> <output>")
                return false
            end
            return Compressor.decompressFile(args[1], args[2])
            
        elseif command == "analyze" then
            if #args < 1 then
                print("Usage: compress analyze <file>")
                return false
            end
            return Compressor.analyzeFile(args[1])
            
        elseif command == "package" then
            if #args < 2 then
                print("Usage: compress package <input> <output>")
                return false
            end
            return Compressor.compressPackage(args[1], args[2])
            
        elseif command == "unpackage" then
            if #args < 2 then
                print("Usage: compress unpackage <input> <output>")
                return false
            end
            return Compressor.decompressPackage(args[1], args[2])
            
        elseif command == "benchmark" then
            if #args < 1 then
                print("Usage: compress benchmark <file>")
                return false
            end
            return Compressor.benchmark(args[1])
            
        else
            print("Commande inconnue: " .. command)
            return false
        end
    end
}

-- Ajouter les commandes du gestionnaire de paquets
commands.pkg = function(args)
    if not args[1] then
        print("Usage:")
        print("  pkg install <package>  - Installe un paquet")
        print("  pkg remove <package>   - Désinstalle un paquet")
        print("  pkg list              - Liste tous les paquets")
        print("  pkg search <query>     - Recherche des paquets")
        print("  pkg create            - Crée une nouvelle application")
        print("  pkg publish           - Publie une application")
        print("  pkg pack <app>        - Crée une archive .advp")
        return true
    end
    
    local command = args[1]
    table.remove(args, 1)
    
    if command == "create" then
        -- Assistant de création d'application
        print("=== Création d'une nouvelle application ===")
        
        -- Informations de base
        write("Nom de l'application: ")
        local name = read()
        if not name:match("^[%w_-]+$") then
            print("Nom invalide (utilisez lettres, chiffres, - et _)")
            return false
        end
        
        write("Description: ")
        local description = read()
        
        write("Auteur: ")
        local author = read()
        
        write("Version [1.0.0]: ")
        local version = read()
        if version == "" then version = "1.0.0" end
        
        -- Créer la structure
        local appDir = fs.combine(AppSystem.APPS_DIR, name)
        if VFS.exists(appDir) then
            print("Une application avec ce nom existe déjà")
            return false
        end
        
        VFS.makeDir(appDir)
        VFS.makeDir(fs.combine(appDir, name))
        VFS.makeDir(fs.combine(appDir, "data"))
        
        -- Créer app.adv
        local metadata = {
            name = name,
            version = version,
            author = author,
            description = description,
            category = "misc",
            created = os.epoch("local"),
            modified = os.epoch("local"),
            permissions = {
                fs = "app",
                net = false,
                term = "full",
                env = "sandbox"
            },
            commands = {},
            dependencies = {}
        }
        
        -- Demander les commandes
        print("\nDéfinition des commandes (laissez vide pour terminer)")
        while true do
            write("\nNom de la commande: ")
            local cmdName = read()
            if cmdName == "" then break end
            
            if not cmdName:match("^[%w_-]+$") then
                print("Nom de commande invalide")
                goto continue
            end
            
            write("Description de la commande: ")
            local cmdDesc = read()
            
            print("Code de la commande (terminez par une ligne vide):")
            local lines = {}
            while true do
                local line = read()
                if line == "" then break end
                table.insert(lines, line)
            end
            
            metadata.commands[cmdName] = {
                description = cmdDesc,
                code = table.concat(lines, "\n")
            }
            
            ::continue::
        end
        
        -- Créer le fichier principal
        local mainCode = [[
-- Application ]] .. name .. [[

-- Variables globales
local APP_PATH = APP_PATH
local APP_DATA = APP_DATA
local APP_INFO = APP_INFO

-- Fonction principale
local function main()
    term.clear()
    term.setCursorPos(1, 1)
    
    -- En-tête
    term.setTextColor(colors.yellow)
    print("=== " .. APP_INFO.name .. " v" .. APP_INFO.version .. " ===")
    print(APP_INFO.description)
    print("Par " .. APP_INFO.author)
    print(string.rep("=", 40))
    term.setTextColor(colors.white)
    
    -- Code de l'application ici
    print("\nBienvenue dans votre application!")
    
    -- Exemple de sauvegarde
    local data = {
        lastRun = os.epoch("local")
    }
    
    local file = fs.open(fs.combine(APP_DATA, "data.json"), "w")
    file.write(textutils.serializeJSON(data))
    file.close()
end

-- Lancer l'application
main()
]]
        
        VFS.writeFile(fs.combine(appDir, name, "main.lua"), mainCode)
        VFS.writeFile(fs.combine(appDir, "app.adv"), textutils.serialize(metadata))
        
        print("\nApplication créée avec succès!")
        print("Structure:")
        print(appDir .. "/")
        print("  ├── app.adv     (métadonnées)")
        print("  ├── " .. name .. "/")
        print("  │   └── main.lua  (code principal)")
        print("  └── data/       (données)")
        
        print("\nPour créer l'archive:")
        print("  pkg pack " .. name)
        
    elseif command == "pack" then
        if not args[1] then
            print("Usage: pkg pack <app>")
            return false
        end
        
        local name = args[1]
        local appDir = fs.combine(AppSystem.APPS_DIR, name)
        
        if not VFS.exists(appDir) then
            print("Application non trouvée")
            return false
        end
        
        local archivePath = name .. ".advp"
        print("Création de l'archive " .. archivePath .. "...")
        
        local success = AppSystem.createPackage(appDir, archivePath)
        if not success then
            print("Erreur lors de la création de l'archive")
            return false
        end
        
        print("Archive créée avec succès!")
        print("\nPour publier votre application:")
        print("1. Hébergez " .. archivePath .. " en ligne")
        print("2. Ajoutez l'entrée suivante à packages.json:")
        print(textutils.serializeJSON({
            [name] = {
                name = name,
                version = "1.0.0",
                description = "Description",
                download = "URL_DE_VOTRE_ARCHIVE",
                dependencies = {}
            }
        }, true))
        
    elseif command == "publish" then
        print("Pour publier votre application:")
        print("1. Créez l'archive avec 'pkg pack <app>'")
        print("2. Hébergez l'archive .advp en ligne")
        print("3. Faites un fork du dépôt CC-pkg")
        print("4. Ajoutez votre application à packages.json")
        print("5. Créez une pull request")
        
    elseif command == "install" then
        if not args[1] then
            print("Spécifiez le nom du paquet à installer")
            return false
        end
        return _G.AppSystem.installPackage(args[1])
        
    elseif command == "remove" or command == "uninstall" then
        if not args[1] then
            print("Spécifiez le nom du paquet à désinstaller")
            return false
        end
        return _G.AppSystem.uninstallPackage(args[1])
        
    elseif command == "list" then
        return _G.AppSystem.listPackages(false)
        
    elseif command == "search" then
        if not args[1] then
            print("Spécifiez un terme de recherche")
            return false
        end
        return _G.AppSystem.searchPackages(args[1])
        
    elseif command == "installed" then
        return _G.AppSystem.listPackages(true)
        
    elseif command == "update" then
        if args[1] then
            return _G.AppSystem.update(args[1])
        else
            local updates, systemUpdate = _G.AppSystem.checkUpdates()
            if #updates == 0 and not systemUpdate then
                print("Tous les paquets sont à jour")
                return true
            end
            
            for _, update in ipairs(updates) do
                print("Mise à jour de " .. update.name .. "...")
                local success, err = _G.AppSystem.update(update.name)
                if not success then
                    print("Erreur: " .. (err or ""))
                end
            end
            
            if systemUpdate then
                print("\nUne mise à jour système est disponible.")
                print("Utilisez 'pkg system-update' pour l'installer.")
            end
            return true
        end
        
    elseif command == "check-updates" then
        local updates, systemUpdate = _G.AppSystem.checkUpdates()
        
        if #updates == 0 and not systemUpdate then
            print("Tous les paquets sont à jour")
            return true
        end
        
        if #updates > 0 then
            print("Mises à jour disponibles:")
            for _, update in ipairs(updates) do
                print(string.format("  %s: %s -> %s", 
                    update.name, 
                    update.currentVersion, 
                    update.newVersion))
            end
        end
        
        if systemUpdate then
            print("\nMise à jour système disponible:")
            print(string.format("  AdvOS: %s -> %s",
                systemUpdate.currentVersion,
                systemUpdate.newVersion))
        end
        return true
        
    elseif command == "system-update" then
        return _G.AppSystem.systemUpdate()
        
    else
        print("Commande inconnue. Tapez 'pkg' pour l'aide")
        return false
    end
end

-- Ajouter les commandes pour gérer les applications
commands.app = function(args)
        if not args[1] then
        print("Usage:")
        print("  app run <nom>    - Lance une application")
        print("  app list        - Liste les applications")
        print("  app info <nom>   - Affiche les informations d'une application")
        return true
    end
    
    local command = args[1]
    table.remove(args, 1)
    
    if command == "run" then
        if not args[1] then
            print("Spécifiez le nom de l'application")
            return false
        end
        
        local success, err = AppManager.runApp(args[1])
        if not success then
            print("Erreur: " .. (err or ""))
            return false
        end
        
    elseif command == "list" then
        local apps = AppManager.listApps()
        
        term.setTextColor(colors.cyan)
        print("=== Applications installées ===")
        term.setTextColor(colors.white)
        
        for _, app in ipairs(apps) do
            print("\n" .. app.name .. " v" .. app.info.version)
            term.setTextColor(colors.gray)
            print("  " .. app.info.description)
            print("  Par " .. app.info.author)
            term.setTextColor(colors.white)
        end
        
    elseif command == "info" then
        if not args[1] then
            print("Spécifiez le nom de l'application")
            return false
        end
        
        local info = AppManager.loadAppInfo(args[1])
        if not info then
            print("Application non trouvée")
            return false
        end
        
        term.setTextColor(colors.cyan)
        print("=== " .. info.name .. " ===")
        term.setTextColor(colors.white)
        print("Version: " .. info.version)
        print("Auteur: " .. info.author)
        print("Description: " .. info.description)
        print("Catégorie: " .. info.category)
        print("\nPermissions:")
        for perm, value in pairs(info.permissions) do
            print("  " .. perm .. ": " .. tostring(value))
        end
        
        if next(info.dependencies) then
            print("\nDépendances:")
            for _, dep in ipairs(info.dependencies) do
                print("  - " .. dep)
            end
        end
        
    else
        print("Commande inconnue. Tapez 'app' pour l'aide")
        return false
    end
    
    return true
end

-- Commandes pour la gestion des processus en arrière-plan
commands.bg = function(args)
    if not args[1] then
        print("Usage: bg <file> [args...]")
        print("Lance un programme en arrière-plan")
        return false
    end
    
    local filePath = resolvePath(args[1])
    table.remove(args, 1)
    
    local processId = advos.shell.runBackground(filePath, table.unpack(args))
    if processId then
        print("Programme lancé en arrière-plan avec l'ID: " .. processId)
        return true
    else
        return false
    end
end

commands.ps = function(args)
    advos.shell.listProcesses()
    return true
end

commands.kill = function(args)
    if not args[1] then
        print("Usage: kill <process_id>")
        return false
    end
    
    local processId = tonumber(args[1])
    if not processId then
        print("ID de processus invalide")
        return false
    end
    
    local success = advos.shell.killProcess(processId)
    return success
end

-- Système d'historique du shell
local ShellHistory = {
    file = "/.AdvOS/history",
    maxSize = 100,
    entries = {},
    
    load = function()
        if VFS.exists(ShellHistory.file) then
            local content = VFS.readFile(ShellHistory.file)
            if content then
                ShellHistory.entries = textutils.unserialize(content) or {}
            end
        end
    end,
    
    save = function()
        VFS.writeFile(ShellHistory.file, textutils.serialize(ShellHistory.entries))
    end,
    
    add = function(command)
        if #ShellHistory.entries > 0 and ShellHistory.entries[#ShellHistory.entries] == command then
            return
        end
        
        table.insert(ShellHistory.entries, command)
        while #ShellHistory.entries > ShellHistory.maxSize do
            table.remove(ShellHistory.entries, 1)
        end
        
        ShellHistory.save()
    end,
    
    get = function(index)
        if index > 0 and index <= #ShellHistory.entries then
            return ShellHistory.entries[index]
        end
        return nil
    end,
    
    size = function()
        return #ShellHistory.entries
    end
}

-- Système d'autocomplétion
ShellCompletion = {
    getCommands = function(input)
        local results = {}
        for name, _ in pairs(commandSystem.commands) do
            if name:sub(1, #input) == input then
                table.insert(results, name)
            end
        end
        return results
    end,
    
    getFiles = function(path)
        path = path or ""
        local results = {}
        
        -- Obtenir le chemin absolu
        local fullPath = resolvePath(path)
        local dir = VFS.getParentPath(fullPath)
        local name = VFS.getBaseName(fullPath) or ""
        
        -- Lister les fichiers
        local files = VFS.list(dir)
        if files then
            for _, file in ipairs(files) do
                if name == "" or file:sub(1, #name) == name then
                    if dir == "/" then
                        table.insert(results, "/" .. file)
                    else
                        table.insert(results, dir .. "/" .. file)
                    end
                end
            end
        end
        
        return results
    end,
    
    complete = function(line)
        local words = {}
        for word in line:gmatch("%S+") do
            table.insert(words, word)
        end
        
        if #words == 0 or (#words == 1 and not line:match("%s$")) then
            -- Compléter la commande
            return ShellCompletion.getCommands(words[1] or "")
        else
            -- Compléter le chemin
            return ShellCompletion.getFiles(words[#words])
        end
    end
}

-- Fonction de lecture améliorée avec indicateur de curseur
local function readCommand()
    local input = ""
    local pos = 0
    local historyPos = ShellHistory.size() + 1
    
    local function redraw()
        local x, y = term.getCursorPos()
        term.clearLine()
        term.setCursorPos(1, y)
        term.setTextColor(colors.green)
        write("AdvOS:" .. currentPath .. "> ")
        term.setTextColor(colors.white)
        
        -- Afficher le texte avec indicateur de curseur
        local beforeCursor = input:sub(1, pos)
        local afterCursor = input:sub(pos + 1)
        
        write(beforeCursor)
        term.setTextColor(colors.yellow)
        write("|") -- Indicateur de curseur
        term.setTextColor(colors.white)
        write(afterCursor)
        
        -- Repositionner le curseur
        term.setCursorPos(pos + #("AdvOS:" .. currentPath .. "> ") + 1, y)
    end
    
    while true do
        redraw()
        local event, param = os.pullEvent()
        
        if event == "key" then
            if param == keys.enter then
                print()
                if input:match("%S") then
                    ShellHistory.add(input)
                end
                return input
            elseif param == keys.backspace and pos > 0 then
                input = input:sub(1, pos - 1) .. input:sub(pos + 1)
                pos = pos - 1
            elseif param == keys.delete and pos < #input then
                input = input:sub(1, pos) .. input:sub(pos + 2)
            elseif param == keys.left and pos > 0 then
                pos = pos - 1
            elseif param == keys.right and pos < #input then
                pos = pos + 1
            elseif param == keys.up then
                if historyPos > 1 then
                    historyPos = historyPos - 1
                    input = ShellHistory.get(historyPos) or ""
                    pos = #input
                end
            elseif param == keys.down then
                if historyPos < ShellHistory.size() then
                    historyPos = historyPos + 1
                    input = ShellHistory.get(historyPos) or ""
                    pos = #input
                else
                    historyPos = ShellHistory.size() + 1
                    input = ""
                    pos = 0
                end
            elseif param == keys.tab then
                local completions = ShellCompletion.complete(input)
                if #completions == 1 then
                    -- Complétion unique
                    local words = {}
                    for word in input:gmatch("%S+") do
                        table.insert(words, word)
                    end
                    
                    if #words == 0 then
                        input = completions[1]
                    else
                        words[#words] = completions[1]
                        input = table.concat(words, " ")
                    end
                    pos = #input
                elseif #completions > 1 then
                    -- Afficher les suggestions
                    print()
                    term.setTextColor(colors.gray)
                    for _, comp in ipairs(completions) do
                        print(comp)
                    end
                    term.setTextColor(colors.white)
                    print()
                end
            elseif param == keys.c then
                -- Ctrl+C désactivé - ne fait rien
            elseif param == keys.v then
                -- Ctrl+V désactivé - ne fait rien
            end
        elseif event == "char" then
            input = input:sub(1, pos) .. param .. input:sub(pos + 1)
            pos = pos + 1
        end
    end
end



-- Fonction principale
local function main()
    -- Initialisation
    print("Initialisation d'AdvOS...")
    sleep(2)
    VFS.init()
    print("VFS initialisé")
    sleep(2)
    -- Charger le remplacement de fs
    print("Chargement du remplacement fs -> VFS...")
    local success, err = pcall(function()
      -- Utiliser shell.run de CraftOS seulement pour charger fs_vfs.lua
      shell.run("fs_vfs.lua")
    end)
    if not success then
      print("Erreur lors du chargement de fs_vfs.lua: " .. tostring(err))
    else
      sleep(2)
      print("fs_vfs.lua chargé avec succès")
    end
    
    commandSystem.loadCommands()
    print("Commandes chargées")
    ShellHistory.load()  -- Charger l'historique au démarrage
    print("Historique chargé")
    
    -- Activer le monkey-patch fs -> VFS (maintenant désactivé)
    setupFsRedirect()
    
    -- Lancer automatiquement .advos/os/startup s'il existe
    advos.launchStartup()
    
    -- Message de bienvenue

    sleep(2)
    term.setTextColor(colors.yellow)
    print("AdvOS v1.0")
    print("Tapez 'help' pour la liste des commandes")
    term.setTextColor(colors.white)
    
    -- Boucle principale
    while true do
        -- Lire la commande
        local input = readCommand()
        if input == "" then goto continue end
        
        -- Parser la commande
        local parts = {}
        for part in input:gmatch("%S+") do
            table.insert(parts, part)
        end
        
        local cmdName = parts[1]
        table.remove(parts, 1)
        
        -- Exécuter la commande
        local success, error = commandSystem.execute(cmdName, parts)
        if not success and error then
            -- Essayer de lancer un fichier directement
            local filePath = resolvePath(cmdName)
            local content = VFS.readFile(filePath)
            
            if content then
                local extension = filePath:match("%.(%w+)$")
                if extension == "lua" then
                    print("Exécution du fichier Lua: " .. filePath)
                    local success, err = pcall(function()
                        advos.shell.run(filePath)
                    end)
                    if not success then
                        term.setTextColor(colors.red)
                        print("Erreur d'exécution: " .. tostring(err))
                        term.setTextColor(colors.white)
                    end
                elseif extension == "adv" then
                    print("Lancement de l'application: " .. filePath)
                    local success, err = pcall(function()
                        advos.shell.run(filePath)
                    end)
                    if not success then
                        term.setTextColor(colors.red)
                        print("Erreur de lancement: " .. tostring(err))
                        term.setTextColor(colors.white)
                    end
                else
                    term.setTextColor(colors.red)
                    print(error)
                    term.setTextColor(colors.white)
                end
            else
                term.setTextColor(colors.red)
                print(error)
                term.setTextColor(colors.white)
            end
        end
        
        ::continue::
    end
end

-- Démarrer le shell avec gestion d'erreur
debug("Starting shell...")
local success, err = pcall(main)
if not success then
        term.setTextColor(colors.red)
        print("Shell crashed: " .. tostring(err))
        term.setTextColor(colors.white)
    debug("Shell crashed: " .. tostring(err))
    crashCount = crashCount + 1
    os.sleep(5)
    os.reboot()
end

-- Protection : désactive os.exit pour empêcher de quitter le shell AdvOS
os.exit = function()
  print("Interdit : impossible de quitter AdvOS.")
end

-- Système de gestion de paquets et d'applications AdvOS
local PackageManager = {
    -- Configuration
    PACKAGES_DIR = "/.AdvOS/packages",
    APPS_DIR = "/.AdvOS/apps",
    REPOSITORY_URL = "https://raw.githubusercontent.com/advos/packages/main",
    
    -- Initialisation
    init = function()
        if not VFS.exists(PackageManager.PACKAGES_DIR) then
            VFS.makeDir(PackageManager.PACKAGES_DIR)
        end
        if not VFS.exists(PackageManager.APPS_DIR) then
            VFS.makeDir(PackageManager.APPS_DIR)
        end
    end,
    
    -- Installer un paquet
    install = function(packageName)
        print("Installation de " .. packageName .. "...")
        
        -- Vérifier si le paquet existe localement
        local localPath = PackageManager.PACKAGES_DIR .. "/" .. packageName .. ".advp"
        if VFS.exists(localPath) then
            return PackageManager.installFromFile(localPath)
        end
        
        -- Essayer de télécharger depuis le repository
        local url = PackageManager.REPOSITORY_URL .. "/" .. packageName .. ".advp"
        print("Téléchargement depuis " .. url)
        
        local response = http.get(url)
        if not response then
            print("Erreur: Impossible de télécharger le paquet")
            return false
        end
        
        local content = response.readAll()
        response.close()
        
        -- Sauvegarder temporairement
        local tempPath = "/.AdvOS/temp/" .. packageName .. ".advp"
        VFS.writeFile(tempPath, content)
        
        local success = PackageManager.installFromFile(tempPath)
        VFS.delete(tempPath)
        
        return success
    end,
    
    -- Installer depuis un fichier
    installFromFile = function(filePath)
        local content = VFS.readFile(filePath)
        if not content then
            print("Erreur: Fichier introuvable")
            return false
        end
        
        -- Désérialiser le paquet
        local package = textutils.unserialize(content)
        if not package then
            print("Erreur: Format de paquet invalide")
            return false
        end
        
        -- Vérifier les dépendances
        for _, dep in ipairs(package.dependencies or {}) do
            if not PackageManager.isInstalled(dep) then
                print("Dépendance manquante: " .. dep)
                write("Installer automatiquement? (o/n): ")
                local response = read()
                if response:lower() == "o" then
                    if not PackageManager.install(dep) then
                        print("Échec de l'installation de la dépendance")
                        return false
                    end
                else
                    print("Installation annulée")
                    return false
                end
            end
        end
        
        -- Installer les fichiers
        local appDir = PackageManager.APPS_DIR .. "/" .. package.name
        VFS.makeDir(appDir)
        
        for path, data in pairs(package.files) do
            local fullPath = appDir .. "/" .. path
            local dir = fullPath:match("(.*)/[^/]*$")
            if dir then
                VFS.makeDir(dir)
            end
            VFS.writeFile(fullPath, data)
        end
        
        -- Enregistrer les métadonnées
        VFS.writeFile(appDir .. "/package.adv", textutils.serialize(package))
        
        print("Paquet installé avec succès: " .. package.name .. " v" .. package.version)
        return true
    end,
    
    -- Désinstaller un paquet
    remove = function(packageName)
        local appDir = PackageManager.APPS_DIR .. "/" .. packageName
        if not VFS.exists(appDir) then
            print("Paquet non trouvé: " .. packageName)
            return false
        end
        
        -- Vérifier les dépendances
        local packageFile = appDir .. "/package.adv"
        if VFS.exists(packageFile) then
            local content = VFS.readFile(packageFile)
            local package = textutils.unserialize(content)
            if package then
                for _, dep in ipairs(package.dependencies or {}) do
                    if PackageManager.isInstalled(dep) then
                        print("Attention: " .. packageName .. " est une dépendance de " .. dep)
                    end
                end
            end
        end
        
        -- Supprimer le répertoire
        PackageManager.removeDirectory(appDir)
        print("Paquet désinstallé: " .. packageName)
        return true
    end,
    
    -- Supprimer un répertoire récursivement
    removeDirectory = function(path)
        local files = VFS.list(path)
        if files then
            for _, file in ipairs(files) do
                local fullPath = path .. "/" .. file
                if VFS.isDir(fullPath) then
                    PackageManager.removeDirectory(fullPath)
                else
                    VFS.delete(fullPath)
                end
            end
        end
        VFS.delete(path)
    end,
    
    -- Lister les paquets installés
    list = function()
        local packages = {}
        local files = VFS.list(PackageManager.APPS_DIR)
        
        if files then
            for _, dir in ipairs(files) do
                local packageFile = PackageManager.APPS_DIR .. "/" .. dir .. "/package.adv"
                if VFS.exists(packageFile) then
                    local content = VFS.readFile(packageFile)
                    local package = textutils.unserialize(content)
                    if package then
                        table.insert(packages, package)
                    end
                end
            end
        end
        
        return packages
    end,
    
    -- Vérifier si un paquet est installé
    isInstalled = function(packageName)
        local appDir = PackageManager.APPS_DIR .. "/" .. packageName
        return VFS.exists(appDir)
    end,
    
    -- Créer un nouveau paquet
    create = function(name, description, author, version)
        print("=== Création d'un nouveau paquet ===")
        
        local package = {
            name = name,
            description = description or "",
            author = author or "Unknown",
            version = version or "1.0.0",
            created = os.epoch("local"),
            modified = os.epoch("local"),
            dependencies = {},
            files = {},
            commands = {}
        }
        
        -- Demander les fichiers à inclure
        print("\nFichiers à inclure (laissez vide pour terminer):")
        while true do
            write("Chemin du fichier: ")
            local filePath = read()
            if filePath == "" then break end
            
            local content = VFS.readFile(filePath)
            if content then
                package.files[filePath] = content
                print("Ajouté: " .. filePath)
            else
                print("Fichier introuvable: " .. filePath)
            end
        end
        
        -- Demander les commandes
        print("\nCommandes à ajouter (laissez vide pour terminer):")
        while true do
            write("Nom de la commande: ")
            local cmdName = read()
            if cmdName == "" then break end
            
            write("Description: ")
            local cmdDesc = read()
            
            print("Code de la commande (terminez par une ligne vide):")
            local lines = {}
            while true do
                local line = read()
                if line == "" then break end
                table.insert(lines, line)
            end
            
            package.commands[cmdName] = {
                description = cmdDesc,
                code = table.concat(lines, "\n")
            }
        end
        
        -- Demander les dépendances
        print("\nDépendances (laissez vide pour terminer):")
        while true do
            write("Nom du paquet: ")
            local dep = read()
            if dep == "" then break end
            table.insert(package.dependencies, dep)
        end
        
        -- Sauvegarder le paquet
        local packagePath = PackageManager.PACKAGES_DIR .. "/" .. name .. ".advp"
        local serialized = textutils.serialize(package)
        VFS.writeFile(packagePath, serialized)
        
        print("\nPaquet créé: " .. packagePath)
        return true
    end,
    
    -- Packager une application existante
    pack = function(appName)
        local appDir = PackageManager.APPS_DIR .. "/" .. appName
        if not VFS.exists(appDir) then
            print("Application non trouvée: " .. appName)
            return false
        end
        
        local packageFile = appDir .. "/package.adv"
        if not VFS.exists(packageFile) then
            print("Fichier package.adv introuvable")
            return false
        end
        
        local content = VFS.readFile(packageFile)
        local package = textutils.unserialize(content)
        if not package then
            print("Erreur: Format de package invalide")
            return false
        end
        
        -- Collecter tous les fichiers
        package.files = {}
        PackageManager.collectFiles(appDir, "", package.files)
        
        -- Mettre à jour la date de modification
        package.modified = os.epoch("local")
        
        -- Sauvegarder le paquet
        local packagePath = PackageManager.PACKAGES_DIR .. "/" .. appName .. ".advp"
        local serialized = textutils.serialize(package)
        VFS.writeFile(packagePath, serialized)
        
        print("Paquet créé: " .. packagePath)
        return true
    end,
    
    -- Collecter les fichiers récursivement
    collectFiles = function(basePath, relativePath, files)
        local fullPath = basePath .. (relativePath ~= "" and "/" .. relativePath or "")
        local items = VFS.list(fullPath)
        
        if items then
            for _, item in ipairs(items) do
                local itemRelativePath = relativePath ~= "" and relativePath .. "/" .. item or item
                local itemFullPath = basePath .. "/" .. itemRelativePath
                
                if VFS.isDir(itemFullPath) then
                    PackageManager.collectFiles(basePath, itemRelativePath, files)
                else
                    local content = VFS.readFile(itemFullPath)
                    if content then
                        files[itemRelativePath] = content
                    end
                end
            end
        end
    end,
    
    -- Rechercher des paquets
    search = function(query)
        print("Recherche de paquets contenant: " .. query)
        
        -- Rechercher dans les paquets locaux
        local files = VFS.list(PackageManager.PACKAGES_DIR)
        if files then
            for _, file in ipairs(files) do
                if file:match("%.advp$") then
                    local content = VFS.readFile(PackageManager.PACKAGES_DIR .. "/" .. file)
                    if content then
                        local package = textutils.unserialize(content)
                        if package and (package.name:lower():find(query:lower()) or 
                                      package.description:lower():find(query:lower())) then
                            print("  " .. package.name .. " v" .. package.version)
                            print("    " .. package.description)
                            print("    Par " .. package.author)
                            print()
                        end
                    end
                end
            end
        end
        
        -- TODO: Recherche en ligne
        print("Recherche en ligne non implémentée")
    end,
    
    -- Mettre à jour un paquet
    update = function(packageName)
        if not PackageManager.isInstalled(packageName) then
            print("Paquet non installé: " .. packageName)
            return false
        end
        
        print("Mise à jour de " .. packageName .. "...")
        
        -- Désinstaller l'ancienne version
        PackageManager.remove(packageName)
        
        -- Installer la nouvelle version
        return PackageManager.install(packageName)
    end,
    
    -- Afficher les informations d'un paquet
    info = function(packageName)
        local appDir = PackageManager.APPS_DIR .. "/" .. packageName
        local packageFile = appDir .. "/package.adv"
        
        if not VFS.exists(packageFile) then
            print("Paquet non trouvé: " .. packageName)
            return false
        end
        
        local content = VFS.readFile(packageFile)
        local package = textutils.unserialize(content)
        if not package then
            print("Erreur: Format de package invalide")
            return false
        end
        
        print("=== " .. package.name .. " v" .. package.version .. " ===")
        print("Description: " .. package.description)
        print("Auteur: " .. package.author)
        print("Créé: " .. os.date("%Y-%m-%d %H:%M:%S", package.created))
        print("Modifié: " .. os.date("%Y-%m-%d %H:%M:%S", package.modified))
        
        if package.dependencies and #package.dependencies > 0 then
            print("\nDépendances:")
            for _, dep in ipairs(package.dependencies) do
                local status = PackageManager.isInstalled(dep) and "✓" or "✗"
                print("  " .. status .. " " .. dep)
            end
        end
        
        if package.commands and next(package.commands) then
            print("\nCommandes:")
            for cmdName, cmd in pairs(package.commands) do
                print("  " .. cmdName .. " - " .. cmd.description)
            end
        end
        
        return true
    end
}

-- Système d'applications AdvOS
local AppManager = {
    -- Lancer une application
    runApp = function(appName, args)
        local appDir = PackageManager.APPS_DIR .. "/" .. appName
        local mainFile = appDir .. "/main.lua"
        
        if not VFS.exists(mainFile) then
            print("Application non trouvée: " .. appName)
            return false
        end
        
        -- Charger les métadonnées
        local packageFile = appDir .. "/package.adv"
        local appInfo = {}
        if VFS.exists(packageFile) then
            local content = VFS.readFile(packageFile)
            appInfo = textutils.unserialize(content) or {}
        end
        
        -- Créer l'environnement de l'application
        local env = createAdvosEnvironment()
        env.APP_PATH = appDir
        env.APP_DATA = appDir .. "/data"
        env.APP_INFO = appInfo
        env.args = args or {}
        
        -- Charger et exécuter l'application
        local content = VFS.readFile(mainFile)
        local fn, err = load(content, "app:" .. appName, "t", env)
        
        if not fn then
            print("Erreur de chargement: " .. err)
            return false
        end
        
        local success, result = pcall(fn)
        if not success then
            print("Erreur d'exécution: " .. tostring(result))
            return false
        end
        
        return true
    end,
    
    -- Lister les applications
    listApps = function()
        local apps = {}
        local files = VFS.list(PackageManager.APPS_DIR)
        
        if files then
            for _, dir in ipairs(files) do
                local mainFile = PackageManager.APPS_DIR .. "/" .. dir .. "/main.lua"
                local packageFile = PackageManager.APPS_DIR .. "/" .. dir .. "/package.adv"
                
                if VFS.exists(mainFile) then
                    local appInfo = { name = dir }
                    if VFS.exists(packageFile) then
                        local content = VFS.readFile(packageFile)
                        local package = textutils.unserialize(content)
                        if package then
                            appInfo = package
                        end
                    end
                    table.insert(apps, appInfo)
                end
            end
        end
        
        return apps
    end
}

-- Initialiser les systèmes
PackageManager.init()

-- Commande pkg
commands.pkg = function(args)
    if not args[1] then
        print("=== Gestionnaire de paquets AdvOS ===")
        print("Usage:")
        print("  pkg install <package>  - Installe un paquet")
        print("  pkg remove <package>   - Désinstalle un paquet")
        print("  pkg list              - Liste tous les paquets")
        print("  pkg search <query>     - Recherche des paquets")
        print("  pkg info <package>     - Affiche les infos d'un paquet")
        print("  pkg update <package>   - Met à jour un paquet")
        print("  pkg create            - Crée un nouveau paquet")
        print("  pkg pack <app>        - Crée un paquet depuis une app")
        return true
    end
    
    local command = args[1]
    table.remove(args, 1)
    
    if command == "install" then
        if not args[1] then
            print("Usage: pkg install <package>")
            return false
        end
        return PackageManager.install(args[1])
        
    elseif command == "remove" then
        if not args[1] then
            print("Usage: pkg remove <package>")
            return false
        end
        return PackageManager.remove(args[1])
        
    elseif command == "list" then
        local packages = PackageManager.list()
        if #packages == 0 then
            print("Aucun paquet installé")
        else
            print("Paquets installés:")
            for _, pkg in ipairs(packages) do
                print("  " .. pkg.name .. " v" .. pkg.version)
                print("    " .. pkg.description)
                print()
            end
        end
        return true
        
    elseif command == "search" then
        if not args[1] then
            print("Usage: pkg search <query>")
            return false
        end
        PackageManager.search(args[1])
        return true
        
    elseif command == "info" then
        if not args[1] then
            print("Usage: pkg info <package>")
            return false
        end
        return PackageManager.info(args[1])
        
    elseif command == "update" then
        if not args[1] then
            print("Usage: pkg update <package>")
            return false
        end
        return PackageManager.update(args[1])
        
    elseif command == "create" then
        print("=== Création d'un nouveau paquet ===")
        write("Nom du paquet: ")
        local name = read()
        if not name:match("^[%w_-]+$") then
            print("Nom invalide (utilisez lettres, chiffres, - et _)")
            return false
        end
        
        write("Description: ")
        local description = read()
        
        write("Auteur: ")
        local author = read()
        
        write("Version [1.0.0]: ")
        local version = read()
        if version == "" then version = "1.0.0" end
        
        return PackageManager.create(name, description, author, version)
        
    elseif command == "pack" then
        if not args[1] then
            print("Usage: pkg pack <app>")
            return false
        end
        return PackageManager.pack(args[1])
        
    else
        print("Commande inconnue: " .. command)
        return false
    end
end

-- Commande app
commands.app = function(args)
    if not args[1] then
        print("=== Gestionnaire d'applications AdvOS ===")
        print("Usage:")
        print("  app run <name> [args...]  - Lance une application")
        print("  app list                  - Liste les applications")
        print("  app info <name>           - Affiche les infos d'une app")
        return true
    end
    
    local command = args[1]
    table.remove(args, 1)
    
    if command == "run" then
        if not args[1] then
            print("Usage: app run <name> [args...]")
            return false
        end
        
        local appName = args[1]
        table.remove(args, 1)
        
        return AppManager.runApp(appName, args)
        
    elseif command == "list" then
        local apps = AppManager.listApps()
        if #apps == 0 then
            print("Aucune application installée")
        else
            print("Applications installées:")
            for _, app in ipairs(apps) do
                print("  " .. app.name .. " v" .. (app.version or "1.0.0"))
                if app.description then
                    print("    " .. app.description)
                end
                print()
            end
        end
        return true
        
    elseif command == "info" then
        if not args[1] then
            print("Usage: app info <name>")
            return false
        end
        
        local appName = args[1]
        local appDir = PackageManager.APPS_DIR .. "/" .. appName
        local packageFile = appDir .. "/package.adv"
        
        if not VFS.exists(packageFile) then
            print("Application non trouvée: " .. appName)
            return false
        end
        
        local content = VFS.readFile(packageFile)
        local app = textutils.unserialize(content)
        if not app then
            print("Erreur: Format d'application invalide")
            return false
        end
        
        print("=== " .. app.name .. " v" .. app.version .. " ===")
        print("Description: " .. app.description)
        print("Auteur: " .. app.author)
        print("Créé: " .. os.date("%Y-%m-%d %H:%M:%S", app.created))
        print("Modifié: " .. os.date("%Y-%m-%d %H:%M:%S", app.modified))
        
        if app.commands and next(app.commands) then
            print("\nCommandes disponibles:")
            for cmdName, cmd in pairs(app.commands) do
                print("  " .. cmdName .. " - " .. cmd.description)
            end
        end
        
        return true
        
    else
        print("Commande inconnue: " .. command)
        return false
    end
end

