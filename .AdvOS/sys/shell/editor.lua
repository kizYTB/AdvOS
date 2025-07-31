-- SPDX-FileCopyrightText: 2017 Daniel Ratcliffe (Adapté pour AdvOS VFS)
--
-- SPDX-License-Identifier: LicenseRef-CCPL

-- Éditeur CraftOS adapté pour AdvOS VFS
local VFS = _G.VFS

-- Get file to edit
local tArgs = { ... }
if #tArgs == 0 then
    local programName = arg[0] or "edit"
    print("Usage: " .. programName .. " <path>")
    return
end

-- Error checking
local sPath = tArgs[1] -- Utiliser directement le chemin VFS
local bReadOnly = false -- Le VFS AdvOS n'est pas en lecture seule

-- Vérifier si c'est un dossier
if VFS.exists(sPath) and VFS.isDir(sPath) then
    print("Cannot edit a directory.")
    return
end

-- Create .lua files by default
if not VFS.exists(sPath) and not string.find(sPath, "%.") then
    local sExtension = "lua" -- Extension par défaut pour AdvOS
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

-- Vérifier l'espace disponible dans le VFS
local message
if term.isColour() then
    message = "Press Ctrl or click here to access menu"
else
    message = "Press Ctrl to access menu"
end

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
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
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
            local ok, _, fileerr  = save(sPath, function(file)
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
            setCursor(x + #param , y)
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
                    -- Move cursor up
                    scrollY = scrollY - 1
                    redrawText()
                end

            elseif param == 1 then
                -- Scroll down
                local nMaxScroll = #tLines - (h - 1)
                if scrollY < nMaxScroll then
                    -- Move cursor down
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