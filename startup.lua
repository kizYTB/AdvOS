settings.set("shell.allow_disk_startup", false)
settings.save()

local run = shell.run

run("/.bootloader/boot.lua")
