local bootloaderDir = "/.bootloader/OS/"
local logoPath = "/.bootloader/Logo/logo.nfp"

local bgColor = colors.gray
local textColor = colors.white
local accentColor = colors.blue
local highlightColor = colors.lightGray
local borderColor = colors.black

os.pullEvent = os.pullEventRaw

local function centerWrite(text, y, color)
    color = color or textColor
    local w, h = term.getSize()
    local x = math.floor((w - #text) / 2) + 1
    term.setCursorPos(x, y)
    term.setTextColor(color)
    term.write(text)
end

local function drawBorder()
    local w, h = term.getSize()
    term.setBackgroundColor(borderColor)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.write("+" .. string.rep("-", w - 2) .. "+")
    term.setCursorPos(1, h)
    term.write("+" .. string.rep("-", w - 2) .. "+")
    for y = 2, h - 1 do
        term.setCursorPos(1, y)
        term.write("|")
        term.setCursorPos(w, y)
        term.write("|")
    end
end

local function drawLoadingBar(percentage)
    local w, h = term.getSize()
    local barLength = w - 4
    local filledLength = math.floor(barLength * percentage)
    term.setCursorPos(2, h - 2)
    term.setBackgroundColor(accentColor)
    term.write(string.rep(" ", filledLength))
    term.setBackgroundColor(colors.black)
    term.write(string.rep(" ", barLength - filledLength))
    term.setCursorPos(2, h - 3)
    term.setTextColor(textColor)
    term.write("Chargement... " .. math.floor(percentage * 100) .. "%")
end

local function drawSpinner(duration, logoPath)
    term.setBackgroundColor(bgColor)
    term.clear()

    if fs.exists(logoPath) then
        term.setCursorPos(1, 1)
        paintutils.drawImage(paintutils.loadImage(logoPath), 1, 1)
    end

    local spinner = { "|", "/", "-", "\\" }
    local w, h = term.getSize()
    local centerX, centerY = math.floor(w / 2), math.floor(h / 2)

    for i = 1, duration * 4 do
        term.setCursorPos(centerX, centerY)
        term.setTextColor(textColor)
        drawLoadingBar(i / (duration * 4))
        sleep(0.25)
    end
end

local function loadOSList()
    local osList = {}
    if fs.exists(bootloaderDir) then
        for _, file in ipairs(fs.list(bootloaderDir)) do
            if file:match("%.json$") then
                local path = bootloaderDir .. file
                local handle = fs.open(path, "r")
                local data = handle.readAll()
                handle.close()
                local ok, osData = pcall(textutils.unserializeJSON, data)
                if ok and osData.name and osData.path then
                    table.insert(osList, osData)
                end
            end
        end
    end
    return osList
end

local function displayMenu(osList)
    term.setBackgroundColor(bgColor)
    term.clear()

    drawBorder()
    centerWrite("Sélectionner un Systeme d'Exploitation", 3)

    for i, osData in ipairs(osList) do
        term.setCursorPos(2, 5 + (i - 1) * 3)
        term.setBackgroundColor(accentColor)
        term.setTextColor(colors.black)
        term.write(string.rep(" ", 2) .. osData.name .. string.rep(" ", 2))
    end

    local selected = 1
    while true do
        for i, osData in ipairs(osList) do
            term.setCursorPos(2, 5 + (i - 1) * 3)
            if i == selected then
                term.setBackgroundColor(highlightColor)
                term.setTextColor(colors.black)
            else
                term.setBackgroundColor(accentColor)
                term.setTextColor(colors.black)
            end
            term.write(string.rep(" ", 2) .. osData.name .. string.rep(" ", 2))
        end

        local _, key = os.pullEvent("key")
        if key == keys.up then
            selected = math.max(1, selected - 1)
        elseif key == keys.down then
            selected = math.min(#osList, selected + 1)
        elseif key == keys.enter then
            return osList[selected]
        end
    end
end

local function bootOS(osData)
    term.setBackgroundColor(bgColor)
    term.clear()
    drawBorder()
    centerWrite("Demarrage de " .. osData.name .. "...", 10)
    sleep(1)
    shell.run(osData.path)
end

local function main()
    drawSpinner(5, logoPath)

    local osList = loadOSList()
    if #osList == 0 then
        term.setBackgroundColor(bgColor)
        term.clear()
        drawBorder()
        centerWrite("Aucun systeme d'exploitation trouvé.", 10)
        sleep(2)
        return
    elseif #osList == 1 then
        bootOS(osList[1])
    else
        local osData = displayMenu(osList)
        bootOS(osData)
    end
end

main()
