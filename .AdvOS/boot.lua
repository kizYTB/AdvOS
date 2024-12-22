local logoPath = "/.AdvOS/assets/start/logo.nfp"

local bgColor = colors.gray
local textColor = colors.white
local accentColor = colors.blue
local highlightColor = colors.lightGray
local borderColor = colors.black
local greenColor = colors.green

os.pullEvent = os.pullEventRaw


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
    term.setBackgroundColor(greenColor)
    term.write(string.rep(" ", filledLength))
    term.setBackgroundColor(colors.black)
    term.write(string.rep(" ", barLength - filledLength))
    term.setCursorPos(2, h - 3)
    term.setTextColor(textColor)
    term.write("Chargement... " .. math.floor(percentage * 100) .. "%")
end

local function drawSpinner(duration, logoPath)
    drawBorder()
    term.setBackgroundColor(bgColor)
    term.clear()

    if fs.exists(logoPath) then
        local image = paintutils.loadImage(logoPath)
        local imgWidth, imgHeight = #image[1], #image
        local w, h = term.getSize()
        
        local centerX = math.floor((w - imgWidth) / 2)
        local centerY = math.floor((h - imgHeight) / 2)

        term.setCursorPos(centerX, centerY)
        paintutils.drawImage(image, centerX, centerY)
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

drawSpinner(10, logoPath)
shell.run("/.AdvOS/sys/shell/shell.lua")