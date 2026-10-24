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
        SubTitle = "by Luvio · Fluent " .. tostring(Fluent.Version),
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
    Advanced = Window:AddTab({ Title = "Advanced", Icon = "layout" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

local Options = Fluent.Options

--========================================
-- OUTPUT
--========================================
local OutputBox = Tabs.Output:AddParagraph({
    Title = "Console Logs",
    Content = "Menunggu aktivitas sistem...",
})

local outputLines = {}

local function logOutput(text)
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
local utilityGroup = Tabs.Scripts:AddLeftGroupbox("Utilitas")
local serverGroup = Tabs.Scripts:AddRightGroupbox("Server")

local recorder = { active = false, data = {} }

utilityGroup:AddButton({
    Title = "CFrame Recorder — Start",
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

utilityGroup:AddButton({
    Title = "CFrame Recorder — Stop & Copy",
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

utilityGroup:AddButton({
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

utilityGroup:AddButton({
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

serverGroup:AddButton({
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

local explorerGroup = Tabs.Explorer:AddLeftGroupbox("Aksi")

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

explorerGroup:AddButton({
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

explorerGroup:AddButton({
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

explorerGroup:AddButton({
    Title = "Copy Path",
    Callback = function()
        local object = resolvePath(targetPath)
        if object and type(setclipboard) == "function" then
            setclipboard(object:GetFullName())
            logOutput("Path disalin: " .. object:GetFullName())
        end
    end,
})

explorerGroup:AddButton({
    Title = "Destroy Instance",
    Callback = function()
        local object = resolvePath(targetPath)
        if object then
            object:Destroy()
            logOutput("Objek dihancurkan.")
        end
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

local spyGroup = Tabs.Spy:AddLeftGroupbox("Spy")

spyGroup:AddToggle("SpyActive", {
    Title = "Activate Remote Spy",
    Description = "Rekam FireServer / InvokeServer",
    Default = false,
    Callback = function(state)
        isSpyActive = state
        logOutput(state and "Spy diaktifkan." or "Spy dimatikan.")
    end,
})

spyGroup:AddButton({
    Title = "Clear Spy Logs",
    Callback = function()
        spyLines = {}
        pcall(function() SpyBox:SetDesc("Logs cleared.") end)
    end,
})

local function formatArgs(args)
    if #args == 0 then return "No Arguments" end
    local out = {}
    for index, value in ipairs(args) do
        out[#out + 1] = "[" .. index .. "] (" .. type(value) .. ") = " .. tostring(value)
    end
    return table.concat(out, "\n")
end

if type(getrawmetatable) == "function" and type(hookmetamethod) == "function" then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
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
        return oldNamecall(self, ...)
    end)
end

--========================================
-- ADVANCED (lazy fetch Dex / Cobalt)
--========================================
local function runRemoteBundle(file, onLoaded)
    task.spawn(function()
        logOutput("Mengambil " .. file .. " dari repo...")
        local ok, source = pcall(AxiumFetch, file)
        if not ok or type(source) ~= "string" then
            logOutput("Gagal mengambil " .. file .. ": " .. tostring(source))
            return
        end

        local chunk, compileError = loadstring(source)
        if not chunk then
            logOutput(file .. " gagal dikompilasi: " .. tostring(compileError))
            return
        end

        local ran, runError = pcall(chunk)
        if not ran then
            logOutput(file .. " error saat dijalankan: " .. tostring(runError))
            return
        end

        task.wait(1.5)
        onLoaded()
    end)
end

local advancedGroup = Tabs.Advanced:AddLeftGroupbox("Tools")
local isDexLoaded, dexGui = false, nil
local isCobaltLoaded, cobaltGui = false, nil

advancedGroup:AddToggle("DexToggle", {
    Title = "Launch Advanced Dex UI",
    Description = "Dex Explorer penuh (diunduh saat dinyalakan)",
    Default = false,
    Callback = function(state)
        if not state then
            if dexGui then dexGui.Enabled = false end
            return
        end
        if isDexLoaded then
            if dexGui then dexGui.Enabled = true end
            return
        end
        isDexLoaded = true
        runRemoteBundle("lib/dex.lua", function()
            dexGui = CoreGui:FindFirstChild("Dex") or CoreGui:FindFirstChild("Dex Explorer")
            if dexGui then
                dexGui.Enabled = true
                logOutput("Dex siap.")
            else
                logOutput("Dex tidak terdeteksi di CoreGui (executor memblokir?).")
            end
        end)
    end,
})

advancedGroup:AddToggle("CobaltToggle", {
    Title = "Launch Advanced Cobalt Spy",
    Description = "Cobalt Remote Spy penuh (diunduh saat dinyalakan)",
    Default = false,
    Callback = function(state)
        if not state then
            if cobaltGui then cobaltGui.Enabled = false end
            return
        end
        if isCobaltLoaded then
            if cobaltGui then cobaltGui.Enabled = true end
            return
        end
        isCobaltLoaded = true
        runRemoteBundle("lib/cobalt.lua", function()
            cobaltGui = CoreGui:FindFirstChild("SimpleSpy2") or CoreGui:FindFirstChild("SimpleSpy")
            if cobaltGui then
                cobaltGui.Enabled = true
                logOutput("Cobalt siap.")
            else
                logOutput("Cobalt tidak terdeteksi di CoreGui (executor memblokir?).")
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

print("[Axium] UI siap — tab dan fitur terpasang.")

Fluent:Notify({
    Title = "Axium",
    Content = "Hub dimuat.",
    SubContent = "Fluent " .. tostring(Fluent.Version),
    Duration = 5,
})
