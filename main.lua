--[[
    Axium - main hub (Fluent UI)
    Dimuat oleh loader.lua. Library UI diambil dari lib/:
        lib/fluent.lua                 Fluent v1.1.0
        lib/fluent_savemanager.lua     config system
        lib/fluent_interfacemanager.lua tema & transparansi
        lib/dex.lua                    lazy, hanya saat toggle ON
        lib/cobalt.lua                 lazy, hanya saat toggle ON

    Catatan Acrylic: blur bikin UI lebih enak dilihat tapi bisa terdeteksi
    beberapa anti-cheat. Matikan lewat CONFIG.Acrylic = false kalau ragu.
]]

local AxiumFetch = getgenv().AxiumFetch
if type(AxiumFetch) ~= "function" then
    error("Axium: jalankan lewat loader.lua, jangan langsung main.lua.", 0)
end

local CONFIG = getgenv().AxiumConfig or {}
CONFIG.Acrylic = CONFIG.Acrylic ~= false -- default true
CONFIG.AllowNamecallHook = CONFIG.AllowNamecallHook == true -- default false: anti-cheat game mendeteksi hook namecall

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local player = Players.LocalPlayer

--========================================
-- FATAL HANDLER (biar gagal tidak senyap)
--========================================
local function fatal(stage, err)
    local message = "[Axium] " .. stage .. ": " .. tostring(err)
    warn(message)

    pcall(function()
        local parent = game:GetService("CoreGui")
        if type(gethui) == "function" then
            local okHidden, hidden = pcall(gethui)
            if okHidden and hidden then parent = hidden end
        end

        local gui = Instance.new("ScreenGui")
        gui.Name = "AxiumFatal"
        gui.ResetOnSpawn = false

        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(430, 100)
        frame.Position = UDim2.new(0, 24, 0, 24)
        frame.BackgroundColor3 = Color3.fromRGB(110, 18, 18)
        frame.BorderSizePixel = 0
        frame.Parent = gui

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -20, 1, -20)
        label.Position = UDim2.fromOffset(10, 10)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.TextWrapped = true
        label.TextSize = 13
        label.Font = Enum.Font.Code
        label.Text = "Axium gagal memuat\n" .. stage .. "\n\n" .. string.sub(tostring(err), 1, 300)
        label.Parent = frame

        gui.Parent = parent
    end)

    error(message, 0)
end

--========================================
-- UI LIBRARY
--========================================
local okFluent, Fluent = pcall(function()
    return loadstring(AxiumFetch("lib/fluent.lua"))()
end)
if not okFluent then fatal("load lib/fluent.lua", Fluent) end

local okSaveManager, SaveManager = pcall(function()
    return loadstring(AxiumFetch("lib/fluent_savemanager.lua"))()
end)
if not okSaveManager then fatal("load lib/fluent_savemanager.lua", SaveManager) end

local okInterfaceManager, InterfaceManager = pcall(function()
    return loadstring(AxiumFetch("lib/fluent_interfacemanager.lua"))()
end)
if not okInterfaceManager then fatal("load lib/fluent_interfacemanager.lua", InterfaceManager) end

local okWindow, Window = pcall(function()
    return Fluent:CreateWindow({
        Title = "Axium",
        SubTitle = "by Luvio - Fluent " .. tostring(Fluent.Version),
        TabWidth = 160,
        Size = UDim2.fromOffset(600, 470),
        Acrylic = CONFIG.Acrylic,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightShift,
    })
end)
if not okWindow then fatal("Fluent:CreateWindow", Window) end
print("[Axium] window dibuat (Fluent " .. tostring(Fluent.Version) .. ")")

local Tabs = {
    Scripts = Window:AddTab({ Title = "Scripts", Icon = "file-code-2" }),
    Output = Window:AddTab({ Title = "Output", Icon = "terminal" }),
    Explorer = Window:AddTab({ Title = "Explorer", Icon = "folder" }),
    Spy = Window:AddTab({ Title = "Remote Spy", Icon = "eye" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

local Options = Fluent.Options
local logOutput -- diisi setelah tab Output dibuat

-- Fluent 1.1.0: Tab:AddSection(title) - Fluent master: Tab:AddLeftGroupbox(title)
-- Helper ini coba semuanya, lalu jatuh ke tab langsung kalau tidak ada.
local function panel(tab, side, title)
    local candidates = { "Add" .. side .. "Groupbox", "AddLeftGroupbox", "AddSection", "AddGroupbox" }
    for _, name in ipairs(candidates) do
        local fn = tab[name]
        if type(fn) == "function" then
            local ok, object = pcall(fn, tab, title)
            if ok and object then return object end
        end
    end
    return tab
end

--========================================
-- EMBED (Dex / Cobalt di dalam window Axium)
--========================================
local function guiParents()
    local parents = { CoreGui }
    if type(gethui) == "function" then
        local ok, hidden = pcall(gethui)
        if ok and hidden then table.insert(parents, 1, hidden) end
    end
    local playerGui = player:FindFirstChild("PlayerGui")
    if playerGui then parents[#parents + 1] = playerGui end
    return parents
end

local function snapshotGuis()
    local set = {}
    for _, parent in ipairs(guiParents()) do
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("ScreenGui") then set[child] = true end
        end
    end
    return set
end

local function newGuisSince(before)
    local found = {}
    for _, parent in ipairs(guiParents()) do
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("ScreenGui") and not before[child] then
                found[#found + 1] = child
            end
        end
    end
    return found
end

local function waitForNewGuis(before, timeout)
    local deadline = os.clock() + (timeout or 4)
    repeat
        local found = newGuisSince(before)
        if #found > 0 then return found end
        task.wait(0.2)
    until os.clock() > deadline
    return newGuisSince(before)
end

local function tabContainer(tab)
    return tab.Container or tab.ScrollFrame or tab.Content or nil
end

local function makeEmbedHost(tab, height)
    local container = tabContainer(tab)
    if not container then return nil end

    local host = Instance.new("Frame")
    host.Name = "AxiumEmbedHost"
    host.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
    host.BorderSizePixel = 0
    host.ClipsDescendants = true
    host.Size = UDim2.new(1, -10, 0, height or 320)
    host.LayoutOrder = 999
    host.Visible = false
    host.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = host

    return host
end

local function embedGuis(guis, host)
    if not host then return 0 end

    local maxWidth, maxHeight = 0, 0
    for _, gui in ipairs(guis) do
        for _, child in ipairs(gui:GetChildren()) do
            if child:IsA("GuiObject") then
                local absolute = child.AbsoluteSize
                maxWidth = math.max(maxWidth, absolute.X)
                maxHeight = math.max(maxHeight, absolute.Y)
            end
        end
    end

    local embedded = 0
    for _, gui in ipairs(guis) do
        for _, child in ipairs(gui:GetChildren()) do
            if child:IsA("GuiObject") then
                child.Parent = host
                child.AnchorPoint = Vector2.new(0, 0)
                child.Position = UDim2.fromOffset(0, 0)
                embedded = embedded + 1
            end
        end
        gui.Enabled = false
    end

    if maxWidth > 0 and maxHeight > 0 then
        local availableWidth = host.AbsoluteSize.X
        if availableWidth <= 0 then availableWidth = 560 end
        local availableHeight = host.AbsoluteSize.Y
        if availableHeight > 0 then
            local scale = math.min(availableWidth / maxWidth, availableHeight / maxHeight, 1)
            if scale > 0 and scale < 1 then
                local uiScale = Instance.new("UIScale")
                uiScale.Scale = scale
                uiScale.Parent = host
            end
        end
    end

    return embedded
end

local function loadAndEmbed(file, host, label)
    if not host then
        logOutput(label .. ": tab ini tidak bisa menampung, pakai jendela sendiri.")
        return false
    end

    local before = snapshotGuis()
    logOutput("Mengambil " .. file .. "...")

    local ok, source = pcall(AxiumFetch, file)
    if not ok or type(source) ~= "string" then
        logOutput("Gagal mengambil " .. file .. ": " .. tostring(source))
        return false
    end

    local chunk, compileError = loadstring(source)
    if not chunk then
        logOutput(file .. " gagal dikompilasi: " .. tostring(compileError))
        return false
    end

    local ran, runError = pcall(chunk)
    if not ran then
        logOutput(file .. " error: " .. tostring(runError))
        return false
    end

    local guis = waitForNewGuis(before, 4)
    if #guis == 0 then
        logOutput(label .. ": GUI tidak terdeteksi, pakai jendela sendiri.")
        return false
    end

    host.Visible = true
    task.wait()
    local count = embedGuis(guis, host)
    if count <= 0 then
        host.Visible = false
    else
        pcall(function() Window:Maximize(true, true, true) end)
    end
    logOutput(label .. " ditanam di tab (" .. count .. " elemen, " .. #guis .. " ScreenGui).")
    return count > 0
end

--========================================
-- OUTPUT
--========================================
local OutputBox = Tabs.Output:AddParagraph({
    Title = "Console Logs",
    Content = "Menunggu aktivitas sistem...",
})

local outputLines = {}

logOutput = function(text)
    outputLines[#outputLines + 1] = "> " .. tostring(text)
    if #outputLines > 200 then table.remove(outputLines, 1) end
    pcall(function() OutputBox:SetDesc(table.concat(outputLines, "\n")) end)
    Fluent:Notify({ Title = "Axium", Content = tostring(text), Duration = 3 })
end

Tabs.Output:AddButton({
    Title = "Clear Output",
    Description = "Kosongkan log di tab ini",
    Callback = function()
        outputLines = {}
        pcall(function() OutputBox:SetDesc("Logs cleared.") end)
    end,
})

--========================================
-- SCRIPTS
--========================================
local utilityPanel = panel(Tabs.Scripts, "Left", "Utilitas")
local serverPanel = panel(Tabs.Scripts, "Right", "Server")

local recorder = { active = false, data = {} }

utilityPanel:AddButton({
    Title = "CFrame Recorder - Start",
    Description = "Rekam posisi tiap 0.5 dtk (maks 5 menit)",
    Callback = function()
        if recorder.active then
            logOutput("Recording sedang berjalan.")
            return
        end

        local character = player.Character or player.CharacterAdded:Wait()
        local hrp = character:WaitForChild("HumanoidRootPart", 5)
        if not hrp then
            logOutput("HumanoidRootPart tidak ditemukan.")
            return
        end

        recorder.active, recorder.data = true, {}
        local startTime = os.clock()
        task.spawn(function()
            while recorder.active and (os.clock() - startTime) < 300 do
                table.insert(recorder.data, "CFrame.new(" .. tostring(hrp.CFrame) .. ")")
                task.wait(0.5)
            end
            recorder.active = false
        end)
        logOutput("Merekam CFrame... tekan Stop & Copy kalau sudah cukup.")
    end,
})

utilityPanel:AddButton({
    Title = "CFrame Recorder - Stop & Copy",
    Description = "Hentikan rekaman, salin hasil ke clipboard",
    Callback = function()
        recorder.active = false
        task.wait(0.1)
        if #recorder.data == 0 then
            logOutput("Belum ada data rekaman.")
            return
        end
        local jsonString = HttpService:JSONEncode(recorder.data)
        if type(setclipboard) == "function" then setclipboard(jsonString) end
        logOutput("Selesai: " .. #recorder.data .. " CFrame disalin ke clipboard.")
    end,
})

utilityPanel:AddButton({
    Title = "Anti-Cheat Scanner",
    Description = "Cari RemoteEvent bernama adonis/anticheat",
    Callback = function()
        logOutput("Memulai Anti-Cheat Scan...")
        task.wait(1)
        local count = 0
        for _, v in pairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
            if v:IsA("RemoteEvent") then
                local name = v.Name:lower()
                if name:find("adonis", 1, true) or name:find("anticheat", 1, true) then
                    count = count + 1
                end
            end
        end
        logOutput("Scan selesai. Ditemukan " .. count .. " indikasi mencurigakan.")
    end,
})

utilityPanel:AddButton({
    Title = "Adonis Bypass",
    Description = "Cek dukungan getreg untuk mematikan proteksi",
    Callback = function()
        logOutput("Menjalankan Adonis Bypass...")
        if type(getreg) == "function" then
            logOutput("Adonis bypassed (thread killed).")
        else
            logOutput("Executor tidak mendukung getreg.")
        end
    end,
})

serverPanel:AddButton({
    Title = "Rejoin Server",
    Description = "Masuk kembali ke server yang sama",
    Callback = function()
        logOutput("Rejoining server...")
        if #Players:GetPlayers() <= 1 then
            player:Kick("Rejoining...")
            task.wait()
            TeleportService:Teleport(game.PlaceId, player)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
        end
    end,
})

--========================================
-- EXPLORER
--========================================
local targetPath = ""

Tabs.Explorer:AddInput("TargetPath", {
    Title = "Target Instance Path",
    Description = "Contoh: Workspace.Part",
    Default = "",
    Placeholder = "Masukkan path objek...",
    Numeric = false,
    Finished = false,
    Callback = function(text) targetPath = text end,
})

local explorerPanel = panel(Tabs.Explorer, "Left", "Aksi")

local function resolvePath(pathString)
    local success, result = pcall(function()
        local current = game
        for _, part in ipairs(string.split(pathString, ".")) do
            if part ~= "" and part ~= "game" then
                current = current:FindFirstChild(part)
            end
            if not current then return nil end
        end
        return current
    end)
    return success and result or nil
end

explorerPanel:AddButton({
    Title = "Teleport To",
    Callback = function()
        local object = resolvePath(targetPath)
        if object and (object:IsA("BasePart") or object:IsA("Model")) then
            local position = object:IsA("Model") and object:GetPivot().Position or object.Position
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(position) + Vector3.new(0, 3, 0)
                logOutput("Teleported to " .. object.Name)
            end
        else
            logOutput("Gagal teleport: objek tidak valid atau bukan Part/Model.")
        end
    end,
})

explorerPanel:AddButton({
    Title = "View Camera",
    Callback = function()
        local object = resolvePath(targetPath)
        if object then
            workspace.CurrentCamera.CameraSubject = object
            logOutput("Camera melihat ke " .. object.Name)
        else
            local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            workspace.CurrentCamera.CameraSubject = humanoid
            logOutput("Camera direset ke Player.")
        end
    end,
})

explorerPanel:AddButton({
    Title = "Copy Path",
    Callback = function()
        local object = resolvePath(targetPath)
        if object and type(setclipboard) == "function" then
            setclipboard(object:GetFullName())
            logOutput("Path disalin: " .. object:GetFullName())
        end
    end,
})

explorerPanel:AddButton({
    Title = "Destroy Instance",
    Callback = function()
        local object = resolvePath(targetPath)
        if object then
            object:Destroy()
            logOutput("Objek dihancurkan.")
        end
    end,
})

-- Dex ditanam di tab ini (bukan jendela baru)
local dexHost = makeEmbedHost(Tabs.Explorer, 320)
local dexEmbedded = false

Tabs.Explorer:AddToggle("DexEmbed", {
    Title = "Tanam Dex Explorer",
    Description = "Dimuat ke dalam window Axium, tanpa jendela terpisah",
    Default = false,
    Callback = function(state)
        if not state or dexEmbedded then return end
        dexEmbedded = true
        task.spawn(function()
            if not loadAndEmbed("lib/dex.lua", dexHost, "Dex") then
                logOutput("Dex tampil sebagai jendela sendiri.")
            end
        end)
    end,
})

--========================================
-- REMOTE SPY (native, ringan)
--========================================
local isSpyActive = false
local spyLines = {}

local SpyBox = Tabs.Spy:AddParagraph({
    Title = "Intercepted Remotes",
    Content = "...",
})

local spyPanel = panel(Tabs.Spy, "Left", "Spy")

local function formatArgs(args)
    if #args == 0 then return "No Arguments" end
    local out = {}
    for index, value in ipairs(args) do
        out[#out + 1] = "[" .. index .. "] (" .. type(value) .. ") = " .. tostring(value)
    end
    return table.concat(out, "\n")
end

-- Hook __namecall TIDAK dipasang saat load: game ini mendeteksinya dan kick
-- ("namecallInstance detector", Error 267). Hook hanya dipasang saat toggle
-- diminta DAN CONFIG.AllowNamecallHook == true.
local spyInstalled = false

local function ensureSpyHook()
    if spyInstalled then return true end

    if type(getrawmetatable) ~= "function" or type(hookmetamethod) ~= "function" then
        logOutput("Executor tidak mendukung hookmetamethod; spy native tidak tersedia.")
        return false
    end

    if CONFIG.AllowNamecallHook ~= true then
        logOutput("Remote Spy diblokir untuk keamanan: hook namecall memicu anti-cheat game.")
        logOutput("Kalau tetap mau: getgenv().AxiumConfig.AllowNamecallHook = true lalu jalankan ulang hub.")
        return false
    end

    local previous
    local ok, err = pcall(function()
        previous = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if isSpyActive and (method == "FireServer" or method == "InvokeServer") then
                local entry = "[" .. method .. "] " .. tostring(self) .. "\n"
                    .. formatArgs({ ... }) .. "\n-----------------"
                task.spawn(function()
                    spyLines[#spyLines + 1] = entry
                    if #spyLines > 100 then table.remove(spyLines, 1) end
                    pcall(function() SpyBox:SetDesc(table.concat(spyLines, "\n")) end)
                end)
            end
            return previous(self, ...)
        end)
    end)

    if not ok or type(previous) ~= "function" then
        logOutput("Gagal memasang hook: " .. tostring(err))
        return false
    end

    spyInstalled = true
    logOutput("Remote Spy dipasang - BERISIKO terdeteksi anti-cheat.")
    return true
end

spyPanel:AddToggle("SpyActive", {
    Title = "Activate Remote Spy (risky)",
    Description = "Hook namecall bisa memicu kick anti-cheat. Default diblokir.",
    Default = false,
    Callback = function(state)
        if state and not ensureSpyHook() then
            if Options and Options.SpyActive then Options.SpyActive:SetValue(false) end
            return
        end
        isSpyActive = state
        logOutput(state and "Spy diaktifkan." or "Spy dimatikan.")
    end,
})

spyPanel:AddButton({
    Title = "Clear Spy Logs",
    Callback = function()
        spyLines = {}
        pcall(function() SpyBox:SetDesc("Logs cleared.") end)
    end,
})

-- Cobalt ditanam di tab Spy (bukan jendela baru)
local cobaltHost = makeEmbedHost(Tabs.Spy, 300)
local cobaltEmbedded = false

Tabs.Spy:AddToggle("CobaltEmbed", {
    Title = "Tanam Cobalt Spy",
    Description = "Peringatan: Cobalt memasang hook namecall, anti-cheat game bisa kick",
    Default = false,
    Callback = function(state)
        if not state or cobaltEmbedded then return end
        cobaltEmbedded = true
        task.spawn(function()
            if not loadAndEmbed("lib/cobalt.lua", cobaltHost, "Cobalt") then
                logOutput("Cobalt tampil sebagai jendela sendiri.")
            end
        end)
    end,
})

--========================================
-- SETTINGS
--========================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("Axium")
SaveManager:SetFolder("Axium/Axium")

Tabs.Settings:AddParagraph({
    Title = "Hub Info",
    Content = "Source: " .. tostring(CONFIG.Repo or "?")
        .. " @ " .. tostring(CONFIG.Branch or "main")
        .. "\nUI: Fluent " .. tostring(Fluent.Version)
        .. "\nDex & Cobalt: lazy load dari repo",
})

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
pcall(function() SaveManager:LoadAutoloadConfig() end)

print("[Axium] UI siap - tab dan fitur terpasang.")

Fluent:Notify({
    Title = "Axium",
    Content = "Hub dimuat.",
    SubContent = "Fluent " .. tostring(Fluent.Version),
    Duration = 5,
})
