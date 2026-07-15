-- BarIndicator.lua
-- A lightweight WoW addon to show a visual indicator of the active action bar.
-- Created by Antigravity.

local addonName, addonTable = ...

-- Forward declarations to resolve scope issues
local optionsFrame, retailCategory, editDialog
local RefreshFrameStyles, UpdateIndicatorVisibility, UpdateMainBarCombatHiding, UpdateIndicator
local RestoreFramePosition, SetFrameScale
local alertFrame, alertOverlayAlert
local RestoreAlertPosition, SetAlertScale, RefreshAlertStyles, UpdateAlertVisibility

-- Helper to deep-copy tables for defaults
local function CopyTable(src)
    if type(src) ~= "table" then return src end
    local res = {}
    for k, v in pairs(src) do
        res[k] = CopyTable(v)
    end
    return res
end

-- Default Settings
local defaults = {
    posX = 0,
    posY = -150,
    point = "CENTER",
    relativePoint = "CENTER",
    locked = false,
    hideMainBarInCombat = true,
    scale = 1.0,
    
    -- Visual Customizations
    fontSize = 24,
    bgAlpha = 0.75,
    borderAlpha = 0.8,
    bar1Color = {0.0, 0.9, 1.0}, -- Default Cyan
    bar2Color = {1.0, 0.6, 0.0}, -- Default Amber/Gold
    
    -- Combat Visibility
    showIndicatorInCombat = true,
    showIndicatorOutCombat = true,
    showBarLabel = true,

    -- Warning Alert Settings
    alert = {
        enabled = true,
        onlyInCombat = false,
        triggerBar = 2,
        text = "WARNING: BAR 2!",
        posX = 0,
        posY = 100,
        point = "CENTER",
        relativePoint = "CENTER",
        scale = 1.2,
        fontSize = 18,
        width = 160,
        height = 36,
        color = {1.0, 0.1, 0.1}, -- Warning Red
        bgAlpha = 0.8,
        borderAlpha = 0.9,
    }
}

-- Print helper
local function PrintMsg(msg)
    print("|cff00e5ffBarIndicator:|r " .. msg)
end

-- Color Presets definition for options swatches
local colorPresets = {
    { name = "Cyan",    color = {0.0, 0.9, 1.0} },
    { name = "Amber",   color = {1.0, 0.6, 0.0} },
    { name = "Red",     color = {1.0, 0.1, 0.1} },
    { name = "Green",   color = {0.1, 1.0, 0.1} },
    { name = "Blue",    color = {0.2, 0.4, 1.0} },
    { name = "Purple",  color = {0.7, 0.1, 1.0} },
    { name = "Orange",  color = {1.0, 0.4, 0.0} },
    { name = "Magenta", color = {1.0, 0.2, 0.6} },
    { name = "Yellow",  color = {1.0, 0.9, 0.0} },
    { name = "White",   color = {1.0, 1.0, 1.0} }
}

-- Create main indicator frame
local frame = CreateFrame("Frame", "BarIndicatorFrame", UIParent, "BackdropTemplate")
frame:SetSize(48, 48)
frame:SetClampedToScreen(true)

-- Restore frame position using unscaled offsets
function RestoreFramePosition()
    local scale = BarIndicatorDB and BarIndicatorDB.scale or 1.0
    if scale <= 0 then scale = 1.0 end
    
    local posX = BarIndicatorDB and BarIndicatorDB.posX or defaults.posX
    local posY = BarIndicatorDB and BarIndicatorDB.posY or defaults.posY
    local point = BarIndicatorDB and BarIndicatorDB.point or defaults.point
    local relPoint = BarIndicatorDB and BarIndicatorDB.relativePoint or defaults.relativePoint
    
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relPoint, posX / scale, posY / scale)
    
    if editDialog and editDialog.UpdatePositionText then
        editDialog:UpdatePositionText()
    end
end

-- Set frame scale and trigger visual refresh without shifting position
function SetFrameScale(newScale)
    newScale = newScale or 1.0
    if newScale <= 0 then newScale = 1.0 end
    
    local oldScale = BarIndicatorDB and BarIndicatorDB.scale or 1.0
    if math.abs(oldScale - newScale) < 0.001 then
        return
    end
    
    if BarIndicatorDB then
        BarIndicatorDB.scale = newScale
    end
    
    if RefreshFrameStyles then
        RefreshFrameStyles()
    end
    
    if editDialog and editDialog.UpdateValues then
        editDialog:UpdateValues()
    end
end

-- Helper: Create a text input EditBox next to a slider for direct manual input
local function CreateEditBoxForSlider(parent, slider, dbKey, minVal, maxVal, step, valueFormat, callback, isAlert)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(40, 20)
    eb:SetPoint("LEFT", slider, "RIGHT", 15, 0)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetMaxLetters(5)
    
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    
    eb:SetScript("OnEditFocusLost", function(self)
        local text = self:GetText()
        local val = tonumber(text)
        if val then
            -- Clamp value to slider min/max
            val = math.max(minVal, math.min(maxVal, val))
            -- Round to nearest step
            val = math.floor(val / step + 0.5) * step
            
            local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
            if db[dbKey] ~= val then
                if dbKey == "scale" then
                    if isAlert then
                        SetAlertScale(val)
                    else
                        SetFrameScale(val)
                    end
                else
                    db[dbKey] = val
                    if callback then callback(val) end
                end
                slider:SetValue(val)
            end
        end
        -- Reset edit box text to current clean value
        local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
        self:SetText(string.format(valueFormat or "%.1f", db[dbKey] or minVal))
    end)
    
    return eb
end

-- Create Edit Mode Overlay Frame
local editOverlay = CreateFrame("Frame", "BarIndicatorEditOverlay", frame, "BackdropTemplate")
editOverlay:SetAllPoints(frame)
editOverlay:SetFrameStrata("HIGH")
editOverlay:SetFrameLevel(99)
editOverlay:Hide()

editOverlay:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = false, tileSize = 0, edgeSize = 1.5,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
editOverlay:SetBackdropColor(1.0, 0.82, 0.0, 0.20) -- Translucent Blizzard Gold
editOverlay:SetBackdropBorderColor(1.0, 0.82, 0.0, 0.8) -- Solid Blizzard Gold

local overlayText = editOverlay:CreateFontString(nil, "OVERLAY")
overlayText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
overlayText:SetPoint("CENTER", editOverlay, "CENTER", 0, 0)
overlayText:SetText("BarIndicator")
overlayText:SetTextColor(1.0, 0.82, 0.0, 1.0)

-- Create the alert frame
alertFrame = CreateFrame("Frame", "BarIndicatorAlertFrame", UIParent, "BackdropTemplate")
alertFrame:SetSize(160, 36)
alertFrame:SetClampedToScreen(true)
alertFrame:SetMovable(true)

-- Alert text FontString
local alertText = alertFrame:CreateFontString(nil, "OVERLAY")
alertText:SetPoint("CENTER", alertFrame, "CENTER", 0, 0)

-- Function to restore alert frame position
function RestoreAlertPosition()
    if not alertFrame then return end
    local scale = BarIndicatorDB and BarIndicatorDB.alert and BarIndicatorDB.alert.scale or 1.2
    if scale <= 0 then scale = 1.2 end
    
    local posX = BarIndicatorDB and BarIndicatorDB.alert.posX or defaults.alert.posX
    local posY = BarIndicatorDB and BarIndicatorDB.alert.posY or defaults.alert.posY
    local point = BarIndicatorDB and BarIndicatorDB.alert.point or defaults.alert.point
    local relPoint = BarIndicatorDB and BarIndicatorDB.alert.relativePoint or defaults.alert.relativePoint
    
    alertFrame:ClearAllPoints()
    alertFrame:SetPoint(point, UIParent, relPoint, posX / scale, posY / scale)
    
    if editDialog and editDialog.context == "alert" and editDialog.UpdatePositionText then
        editDialog:UpdatePositionText()
    end
end

-- Function to set alert frame scale
function SetAlertScale(newScale)
    newScale = newScale or 1.2
    if newScale <= 0 then newScale = 1.2 end
    
    local oldScale = BarIndicatorDB and BarIndicatorDB.alert.scale or 1.2
    if math.abs(oldScale - newScale) < 0.001 then
        return
    end
    
    if BarIndicatorDB and BarIndicatorDB.alert then
        BarIndicatorDB.alert.scale = newScale
    end
    
    if RefreshAlertStyles then
        RefreshAlertStyles()
    end
    
    if editDialog and editDialog.context == "alert" and editDialog.UpdateValues then
        editDialog:UpdateValues()
    end
end

-- Refresh Alert styles and text
function RefreshAlertStyles()
    if not alertFrame then return end
    
    local alertDB = BarIndicatorDB.alert
    alertFrame:SetSize(alertDB.width or 160, alertDB.height or 36)
    alertFrame:SetScale(alertDB.scale or 1.2)
    RestoreAlertPosition()
    
    alertText:SetFont("Fonts\\FRIZQT__.TTF", alertDB.fontSize or 18, "OUTLINE")
    alertText:SetText(alertDB.text or "WARNING: BAR 2!")
    
    local r, g, b = unpack(alertDB.color or defaults.alert.color)
    alertText:SetTextColor(r, g, b)
    
    alertFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = false, tileSize = 0, edgeSize = 1.5,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    alertFrame:SetBackdropColor(0.05, 0.05, 0.05, alertDB.bgAlpha or 0.8)
    alertFrame:SetBackdropBorderColor(r, g, b, alertDB.borderAlpha or 0.9)
end

-- Update alert visibility securely
function UpdateAlertVisibility()
    if not alertFrame then return end
    
    UnregisterStateDriver(alertFrame, "visibility")
    
    if not BarIndicatorDB.alert.enabled then
        alertFrame:Hide()
        return
    end
    
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        alertFrame:Show()
        return
    end
    
    local triggerBar = BarIndicatorDB.alert.triggerBar or 2
    local condition
    if BarIndicatorDB.alert.onlyInCombat then
        condition = string.format("[bar:%d,combat] show; hide", triggerBar)
    else
        condition = string.format("[bar:%d] show; hide", triggerBar)
    end
    RegisterStateDriver(alertFrame, "visibility", condition)
end

-- Create Alert Edit Mode Overlay
alertOverlayAlert = CreateFrame("Frame", "BarIndicatorAlertEditOverlay", alertFrame, "BackdropTemplate")
alertOverlayAlert:SetAllPoints(alertFrame)
alertOverlayAlert:SetFrameStrata("HIGH")
alertOverlayAlert:SetFrameLevel(99)
alertOverlayAlert:Hide()

alertOverlayAlert:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = false, tileSize = 0, edgeSize = 1.5,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
alertOverlayAlert:SetBackdropColor(1.0, 0.82, 0.0, 0.20) -- Translucent Blizzard Gold
alertOverlayAlert:SetBackdropBorderColor(1.0, 0.82, 0.0, 0.8) -- Solid Blizzard Gold

local alertOverlayText = alertOverlayAlert:CreateFontString(nil, "OVERLAY")
alertOverlayText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
alertOverlayText:SetPoint("CENTER", alertOverlayAlert, "CENTER", 0, 0)
alertOverlayText:SetText("BarIndicator Alert")
alertOverlayText:SetTextColor(1.0, 0.82, 0.0, 1.0)

alertOverlayAlert:EnableMouse(true)
alertOverlayAlert:EnableMouseWheel(true)

local alertDragStartX, alertDragStartY
alertOverlayAlert:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        alertDragStartX, alertDragStartY = GetCursorPosition()
        alertFrame:StartMoving()
    end
end)

alertOverlayAlert:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        alertFrame:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = alertFrame:GetPoint()
        local scale = BarIndicatorDB.alert.scale or 1.2
        BarIndicatorDB.alert.point = point
        BarIndicatorDB.alert.relativePoint = relativePoint
        BarIndicatorDB.alert.posX = xOfs * scale
        BarIndicatorDB.alert.posY = yOfs * scale
        
        if editDialog then
            editDialog:UpdatePositionText()
        end
        
        local endX, endY = GetCursorPosition()
        if alertDragStartX and alertDragStartY then
            local dist = math.sqrt((endX - alertDragStartX)^2 + (endY - alertDragStartY)^2)
            if dist < 5 then
                if editDialog:IsShown() and editDialog.context == "alert" then
                    editDialog:Hide()
                else
                    editDialog:SetContext("alert")
                    editDialog:Show()
                end
            end
        end
    elseif button == "RightButton" then
        if editDialog:IsShown() and editDialog.context == "alert" then
            editDialog:Hide()
        else
            editDialog:SetContext("alert")
            editDialog:Show()
        end
    end
end)

alertOverlayAlert:SetScript("OnMouseWheel", function(self, delta)
    local curScale = BarIndicatorDB.alert.scale or 1.2
    local newScale = curScale + (delta * 0.05)
    newScale = math.max(0.5, math.min(3.0, newScale))
    newScale = math.floor(newScale * 100 + 0.5) / 100
    
    SetAlertScale(newScale)
    
    PrintMsg("Alert scale set to |cff00e5ff" .. newScale .. "|r via mouse wheel.")
end)

alertOverlayAlert:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("BarIndicator Alert (Edit Mode)", 1.0, 0.82, 0.0)
    GameTooltip:AddLine("Left Click & Drag to reposition this Alert.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Left/Right Click to toggle Alert Settings.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Scroll Mouse Wheel to resize alert (scale).", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

alertOverlayAlert:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

-- Create the Edit Mode settings dialog
editDialog = CreateFrame("Frame", "BarIndicatorEditModeDialog", UIParent, "BackdropTemplate")
editDialog:SetSize(230, 290)
editDialog:SetFrameStrata("DIALOG")
editDialog:SetFrameLevel(100)
editDialog:Hide()

editDialog:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = false, tileSize = 0, edgeSize = 1.5,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
editDialog:SetBackdropColor(0.12, 0.12, 0.15, 0.95) -- Clean dark slate
editDialog:SetBackdropBorderColor(1.0, 0.82, 0.0, 0.9) -- Blizzard Gold border
editDialog:SetClampedToScreen(true)

-- Title
local dialogTitle = editDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dialogTitle:SetPoint("TOPLEFT", editDialog, "TOPLEFT", 12, -12)
dialogTitle:SetText("BarIndicator Settings")
dialogTitle:SetTextColor(1.0, 0.82, 0.0, 1.0) -- Gold

-- Close button (top right 'X')
local closeBtn = CreateFrame("Button", nil, editDialog, "UIPanelCloseButton")
closeBtn:SetSize(26, 26)
closeBtn:SetPoint("TOPRIGHT", editDialog, "TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
    editDialog:Hide()
end)

-- Position Coordinates Text
local posText = editDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
posText:SetPoint("TOPLEFT", dialogTitle, "BOTTOMLEFT", 0, -6)
posText:SetTextColor(0.8, 0.8, 0.8, 1.0)

function editDialog:UpdatePositionText()
    if self.context == "alert" then
        local x = math.floor(BarIndicatorDB.alert.posX or 0)
        local y = math.floor(BarIndicatorDB.alert.posY or 0)
        posText:SetText(string.format("Position: X: %d, Y: %d", x, y))
    else
        local x = math.floor(BarIndicatorDB.posX or 0)
        local y = math.floor(BarIndicatorDB.posY or 0)
        posText:SetText(string.format("Position: X: %d, Y: %d", x, y))
    end
end

-- Dialog Sliders and Checkboxes Helpers
local function Dialog_CreateSlider(parent, labelText, dbKey, minVal, maxVal, step, valueFormat, yOffset, callback, isAlert)
    local slider = CreateFrame("Slider", "BarIndicatorDialogSlider_" .. dbKey .. (isAlert and "_alert" or ""), parent, "OptionsSliderTemplate")
    slider:SetSize(145, 16)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)
    
    local titleStr = slider.Text or _G[slider:GetName() .. "Text"]
    local lowStr = slider.Low or _G[slider:GetName() .. "Low"]
    local highStr = slider.High or _G[slider:GetName() .. "High"]
    
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    
    if lowStr then lowStr:SetText(tostring(minVal)) end
    if highStr then highStr:SetText(tostring(maxVal)) end
    
    local function GetDBValue()
        local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
        return db[dbKey]
    end
    
    local function SetDBValue(val)
        local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
        db[dbKey] = val
    end
    
    local function UpdateLabel()
        local val = slider:GetValue()
        local formatted = string.format(valueFormat or "%.1f", val)
        if titleStr then
            if slider.editBox then
                titleStr:SetText(labelText)
            else
                titleStr:SetText(labelText .. ": |cff00e5ff" .. formatted .. "|r")
            end
        end
        if slider.editBox and not slider.editBox:HasFocus() then
            slider.editBox:SetText(formatted)
        end
    end
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        if GetDBValue() == value then
            return
        end
        if dbKey == "scale" then
            if isAlert then
                SetAlertScale(value)
            else
                SetFrameScale(value)
            end
        else
            SetDBValue(value)
            if callback then
                callback(value)
            end
        end
        UpdateLabel()
    end)
    
    slider.UpdateValue = function(self)
        self:SetValue(GetDBValue())
        UpdateLabel()
    end
    
    if dbKey == "scale" or dbKey == "fontSize" or dbKey == "triggerBar" or dbKey == "width" or dbKey == "height" then
        slider.editBox = CreateEditBoxForSlider(parent, slider, dbKey, minVal, maxVal, step, valueFormat, callback, isAlert)
    end
    
    return slider
end

local function Dialog_CreateCheckbox(parent, labelText, dbKey, yOffset, callback, isAlert)
    local cb = CreateFrame("CheckButton", "BarIndicatorDialogCB_" .. dbKey .. (isAlert and "_alert" or ""), parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)
    
    local labelStr = cb.Text or _G[cb:GetName() .. "Text"]
    if labelStr then
        labelStr:SetText(labelText)
        labelStr:SetFontObject("GameFontHighlightSmall")
    end
    
    local function GetDBValue()
        local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
        return db[dbKey]
    end
    
    local function SetDBValue(val)
        local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
        db[dbKey] = val
    end
    
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        SetDBValue(checked)
        if callback then
            callback(checked)
        end
    end)
    
    cb.UpdateValue = function(self)
        self:SetChecked(GetDBValue())
    end
    
    return cb
end

-- Create Dialog Controls
editDialog.mainControls = {}
editDialog.alertControls = {}

-- Main Controls
local scaleSlider = Dialog_CreateSlider(editDialog, "Scale", "scale", 0.5, 3.0, 0.1, "%.1f", -55, function(val)
    RefreshFrameStyles()
end, false)
table.insert(editDialog.mainControls, scaleSlider)

local fontSlider = Dialog_CreateSlider(editDialog, "Font Size", "fontSize", 12, 48, 1, "%d", -100, function(val)
    RefreshFrameStyles()
end, false)
table.insert(editDialog.mainControls, fontSlider)

local showInCombatCB = Dialog_CreateCheckbox(editDialog, "Show in Combat", "showIndicatorInCombat", -135, function(val)
    UpdateIndicatorVisibility()
end, false)
table.insert(editDialog.mainControls, showInCombatCB)

local showOutCombatCB = Dialog_CreateCheckbox(editDialog, "Show Out of Combat", "showIndicatorOutCombat", -160, function(val)
    UpdateIndicatorVisibility()
end, false)
table.insert(editDialog.mainControls, showOutCombatCB)

local hideMainCB = Dialog_CreateCheckbox(editDialog, "Hide Main Bar in Combat", "hideMainBarInCombat", -185, function(val)
    UpdateMainBarCombatHiding()
end, false)
table.insert(editDialog.mainControls, hideMainCB)

local showLabelCB = Dialog_CreateCheckbox(editDialog, "Show \"BAR\" Label Text", "showBarLabel", -210, function(val)
    RefreshFrameStyles()
end, false)
table.insert(editDialog.mainControls, showLabelCB)

-- Alert Controls
local alertEnabledCB = Dialog_CreateCheckbox(editDialog, "Enable Alert", "enabled", -55, function(val)
    UpdateAlertVisibility()
end, true)
table.insert(editDialog.alertControls, alertEnabledCB)

local alertTriggerSlider = Dialog_CreateSlider(editDialog, "Trigger Bar", "triggerBar", 1, 6, 1, "%d", -85, function(val)
    UpdateAlertVisibility()
end, true)
table.insert(editDialog.alertControls, alertTriggerSlider)

local alertOnlyInCombatCB = Dialog_CreateCheckbox(editDialog, "Only Show in Combat", "onlyInCombat", -120, function(val)
    UpdateAlertVisibility()
end, true)
table.insert(editDialog.alertControls, alertOnlyInCombatCB)

local alertTextLabel = editDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
alertTextLabel:SetPoint("TOPLEFT", editDialog, "TOPLEFT", 12, -150)
alertTextLabel:SetText("Alert Message:")
alertTextLabel:SetTextColor(0.8, 0.8, 0.8, 1.0)
table.insert(editDialog.alertControls, alertTextLabel)

local alertTextEB = CreateFrame("EditBox", nil, editDialog, "InputBoxTemplate")
alertTextEB:SetSize(145, 20)
alertTextEB:SetPoint("TOPLEFT", editDialog, "TOPLEFT", 15, -170)
alertTextEB:SetAutoFocus(false)
alertTextEB:SetFontObject("GameFontHighlightSmall")
alertTextEB:SetMaxLetters(24)
alertTextEB:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)
alertTextEB:SetScript("OnEditFocusLost", function(self)
    local text = self:GetText()
    if text and text ~= "" then
        BarIndicatorDB.alert.text = text
        RefreshAlertStyles()
    end
end)
alertTextEB.UpdateValue = function(self)
    self:SetText(BarIndicatorDB.alert.text or "WARNING: BAR 2!")
end
table.insert(editDialog.alertControls, alertTextEB)

local alertScaleSlider = Dialog_CreateSlider(editDialog, "Scale", "scale", 0.5, 3.0, 0.1, "%.1f", -205, function(val)
    RefreshAlertStyles()
end, true)
table.insert(editDialog.alertControls, alertScaleSlider)

local alertFontSlider = Dialog_CreateSlider(editDialog, "Font Size", "fontSize", 12, 48, 1, "%d", -250, function(val)
    RefreshAlertStyles()
end, true)
table.insert(editDialog.alertControls, alertFontSlider)

local alertWidthSlider = Dialog_CreateSlider(editDialog, "Width", "width", 60, 400, 5, "%d", -295, function(val)
    RefreshAlertStyles()
end, true)
table.insert(editDialog.alertControls, alertWidthSlider)

local alertHeightSlider = Dialog_CreateSlider(editDialog, "Height", "height", 15, 150, 2, "%d", -340, function(val)
    RefreshAlertStyles()
end, true)
table.insert(editDialog.alertControls, alertHeightSlider)

-- SetContext Method
function editDialog:SetContext(context)
    self.context = context or "main"
    self:UpdatePositionText()
    
    if self.context == "main" then
        dialogTitle:SetText("BarIndicator Settings")
        self:SetSize(230, 290)
        
        for _, ctrl in ipairs(self.mainControls) do
            ctrl:Show()
            if ctrl.editBox then ctrl.editBox:Show() end
        end
        for _, ctrl in ipairs(self.alertControls) do
            ctrl:Hide()
            if ctrl.editBox then ctrl.editBox:Hide() end
        end
        
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, 0)
    else
        dialogTitle:SetText("BI Alert Settings")
        self:SetSize(230, 420)
        
        for _, ctrl in ipairs(self.mainControls) do
            ctrl:Hide()
            if ctrl.editBox then ctrl.editBox:Hide() end
        end
        for _, ctrl in ipairs(self.alertControls) do
            ctrl:Show()
            if ctrl.editBox then ctrl.editBox:Show() end
        end
        
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", alertFrame, "TOPRIGHT", 12, 0)
    end
    
    self:UpdateValues()
end

function editDialog:UpdateValues()
    self:UpdatePositionText()
    local controls = (self.context == "alert") and self.alertControls or self.mainControls
    for _, control in ipairs(controls) do
        if control.UpdateValue then
            control:UpdateValue()
        end
    end
end

-- Dialog Show Script to self-align and refresh values
editDialog:SetScript("OnShow", function(self)
    self:SetContext(self.context or "main")
end)

-- Action Buttons
local moreOptionsBtn = CreateFrame("Button", nil, editDialog, "UIPanelButtonTemplate")
moreOptionsBtn:SetSize(100, 22)
moreOptionsBtn:SetPoint("BOTTOMLEFT", editDialog, "BOTTOMLEFT", 12, 12)
moreOptionsBtn:SetText("More Options")
moreOptionsBtn:SetScript("OnClick", function()
    if Settings and Settings.OpenToCategory and retailCategory then
        Settings.OpenToCategory(retailCategory:GetID())
    else
        InterfaceOptionsFrame_OpenToCategory(optionsFrame)
    end
end)

local resetPosBtnDialog = CreateFrame("Button", nil, editDialog, "UIPanelButtonTemplate")
resetPosBtnDialog:SetSize(100, 22)
resetPosBtnDialog:SetPoint("BOTTOMRIGHT", editDialog, "BOTTOMRIGHT", -12, 12)
resetPosBtnDialog:SetText("Reset Position")
resetPosBtnDialog:SetScript("OnClick", function()
    if editDialog.context == "alert" then
        BarIndicatorDB.alert.point = defaults.alert.point
        BarIndicatorDB.alert.relativePoint = defaults.alert.relativePoint
        BarIndicatorDB.alert.posX = defaults.alert.posX
        BarIndicatorDB.alert.posY = defaults.alert.posY
        RestoreAlertPosition()
        PrintMsg("Alert position reset to default coordinates.")
    else
        BarIndicatorDB.point = defaults.point
        BarIndicatorDB.relativePoint = defaults.relativePoint
        BarIndicatorDB.posX = defaults.posX
        BarIndicatorDB.posY = defaults.posY
        RestoreFramePosition()
        PrintMsg("Position reset to default coordinates.")
    end
end)

-- Dragging & Clicks inside Edit Mode
editOverlay:EnableMouse(true)
editOverlay:EnableMouseWheel(true)

local dragStartX, dragStartY
editOverlay:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        dragStartX, dragStartY = GetCursorPosition()
        frame:StartMoving()
    end
end)

editOverlay:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        frame:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = frame:GetPoint()
        local scale = BarIndicatorDB.scale or 1.0
        BarIndicatorDB.point = point
        BarIndicatorDB.relativePoint = relativePoint
        BarIndicatorDB.posX = xOfs * scale
        BarIndicatorDB.posY = yOfs * scale
        
        if editDialog then
            editDialog:UpdatePositionText()
        end
        
        local endX, endY = GetCursorPosition()
        if dragStartX and dragStartY then
            local dist = math.sqrt((endX - dragStartX)^2 + (endY - dragStartY)^2)
            if dist < 5 then
                if editDialog:IsShown() and editDialog.context == "main" then
                    editDialog:Hide()
                else
                    editDialog:SetContext("main")
                    editDialog:Show()
                end
            end
        end
    elseif button == "RightButton" then
        if editDialog:IsShown() and editDialog.context == "main" then
            editDialog:Hide()
        else
            editDialog:SetContext("main")
            editDialog:Show()
        end
    end
end)

-- Mouse Wheel scaling in Edit Mode
editOverlay:SetScript("OnMouseWheel", function(self, delta)
    local curScale = BarIndicatorDB.scale or 1.0
    local newScale = curScale + (delta * 0.05)
    newScale = math.max(0.5, math.min(3.0, newScale))
    newScale = math.floor(newScale * 100 + 0.5) / 100
    
    SetFrameScale(newScale)
    
    PrintMsg("Scale set to |cff00e5ff" .. newScale .. "|r via mouse wheel.")
end)

-- Overlay Tooltips
editOverlay:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("BarIndicator (Edit Mode)", 1.0, 0.82, 0.0)
    GameTooltip:AddLine("Left Click & Drag to reposition the HUD.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Left/Right Click to toggle Settings Dialog.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Scroll Mouse Wheel to resize (scale).", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

editOverlay:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

-- Create visual components
-- Backdrop setup
frame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = false, tileSize = 0, edgeSize = 1.5,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})

-- Label text ("BAR")
local label = frame:CreateFontString(nil, "OVERLAY")
label:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
label:SetPoint("TOP", frame, "TOP", 0, -6)
label:SetText("BAR")
label:SetTextColor(0.7, 0.7, 0.7, 0.8)

-- Main number text ("1", "2", etc.)
local pageText = frame:CreateFontString(nil, "OVERLAY")
pageText:SetPoint("CENTER", frame, "CENTER", 0, -5)

-- Helper to update the visual appearance of the indicator based on active bar page
function UpdateIndicator()
    local page = GetActionBarPage()
    pageText:SetText(tostring(page))
    
    local r, g, b
    local bg = BarIndicatorDB.bgAlpha or 0.75
    local border = BarIndicatorDB.borderAlpha or 0.8
    
    if page == 1 then
        r, g, b = unpack(BarIndicatorDB.bar1Color or defaults.bar1Color)
    elseif page == 2 then
        r, g, b = unpack(BarIndicatorDB.bar2Color or defaults.bar2Color)
    else
        -- White/Gray theme for other pages
        r, g, b = 1.0, 1.0, 1.0
        border = border * 0.6 -- Fade border opacity slightly for inactive pages
    end
    
    pageText:SetTextColor(r, g, b)
    frame:SetBackdropColor(0.05, 0.05, 0.05, bg)
    frame:SetBackdropBorderColor(r, g, b, border)
end

-- Refresh visual scale and fonts
function RefreshFrameStyles()
    frame:SetScale(BarIndicatorDB.scale or 1.0)
    RestoreFramePosition()
    pageText:SetFont("Fonts\\FRIZQT__.TTF", BarIndicatorDB.fontSize or 24, "OUTLINE")
    
    if BarIndicatorDB.showBarLabel then
        label:Show()
        pageText:ClearAllPoints()
        pageText:SetPoint("CENTER", frame, "CENTER", 0, -5)
    else
        label:Hide()
        pageText:ClearAllPoints()
        pageText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
    
    UpdateIndicator()
end

-- Secure State Driver for combat action bar fading
function UpdateMainBarCombatHiding()
    if not MainMenuBar then
        return
    end

    if BarIndicatorDB.hideMainBarInCombat then
        -- Register a secure state driver to hide MainMenuBar in combat and show out of combat
        RegisterStateDriver(MainMenuBar, "visibility", "[combat] hide; show")
    else
        -- Remove driver and restore visibility
        UnregisterStateDriver(MainMenuBar, "visibility")
        if not InCombatLockdown() then
            MainMenuBar:Show()
        end
    end
end

-- Secure State Driver for indicator frame visibility in/out of combat
function UpdateIndicatorVisibility()
    UnregisterStateDriver(frame, "visibility")
    
    local inCombat = BarIndicatorDB.showIndicatorInCombat
    local outCombat = BarIndicatorDB.showIndicatorOutCombat
    
    if inCombat and outCombat then
        RegisterStateDriver(frame, "visibility", "show")
    elseif inCombat and not outCombat then
        RegisterStateDriver(frame, "visibility", "[combat] show; hide")
    elseif not inCombat and outCombat then
        RegisterStateDriver(frame, "visibility", "[combat] hide; show")
    else
        RegisterStateDriver(frame, "visibility", "hide")
    end
end

-- Drag and Position handlers
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")

frame:SetScript("OnDragStart", function(self)
    if not BarIndicatorDB.locked and IsShiftKeyDown() then
        self:StartMoving()
    end
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    local scale = BarIndicatorDB.scale or 1.0
    BarIndicatorDB.point = point
    BarIndicatorDB.relativePoint = relativePoint
    BarIndicatorDB.posX = xOfs * scale
    BarIndicatorDB.posY = yOfs * scale
end)

frame:SetScript("OnEnter", function(self)
    if not BarIndicatorDB.locked then
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("BarIndicator", 0.0, 0.9, 1.0)
        GameTooltip:AddLine("Shift + Left Click & Drag to reposition.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Type /bi lock to secure in place.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end
end)

frame:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

-- Main Event Handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize Database
        if not BarIndicatorDB then
            BarIndicatorDB = {}
        end
        for k, v in pairs(defaults) do
            if BarIndicatorDB[k] == nil then
                BarIndicatorDB[k] = CopyTable(v)
            elseif type(v) == "table" then
                -- Deep copy missing fields in nested structures
                for subK, subV in pairs(v) do
                    if BarIndicatorDB[k][subK] == nil then
                        BarIndicatorDB[k][subK] = CopyTable(subV)
                    end
                end
            end
        end
        
        -- Migrate position coordinates from old version (v1) to scale-independent (v2)
        if not BarIndicatorDB.posVersion or BarIndicatorDB.posVersion < 2 then
            local scale = BarIndicatorDB.scale or 1.0
            BarIndicatorDB.posX = (BarIndicatorDB.posX or defaults.posX) * scale
            BarIndicatorDB.posY = (BarIndicatorDB.posY or defaults.posY) * scale
            BarIndicatorDB.posVersion = 2
        end
        
        -- Apply styles and visibility
        RefreshFrameStyles()
        UpdateIndicatorVisibility()
        UpdateMainBarCombatHiding()
        
        -- Alert initialization
        RefreshAlertStyles()
        UpdateAlertVisibility()
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateIndicatorVisibility()
        UpdateMainBarCombatHiding()
        UpdateIndicator()
        UpdateAlertVisibility()
        
    elseif event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" then
        UpdateIndicator()
        -- Also trigger update on action bar page change just in case (though secure driver handles visibility)
    end
end)

----------------------------------------------------
-- Options Interface Menu Setup
----------------------------------------------------

optionsFrame = CreateFrame("Frame", "BarIndicatorOptionsFrame", UIParent)
optionsFrame.name = "BarIndicator"

-- Title & Header
local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -16)
title:SetText("BarIndicator Options")

local desc = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
desc:SetText("Configure settings, adjust layout, customize colors, and lock frame positions.")

local headerLine = optionsFrame:CreateTexture(nil, "ARTWORK")
headerLine:SetSize(580, 1)
headerLine:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
headerLine:SetColorTexture(0.3, 0.3, 0.3, 0.4)

-- Helper: Create a Checkbox
local function CreateCheckbox(parent, labelText, dbKey, tooltipText, callback, isAlert)
    local cb = CreateFrame("CheckButton", "BarIndicatorCB_" .. dbKey .. (isAlert and "_alert" or ""), parent, "InterfaceOptionsCheckButtonTemplate")
    local labelStr = cb.Text or _G[cb:GetName() .. "Text"]
    if labelStr then labelStr:SetText(labelText) end
    
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
        db[dbKey] = checked
        if callback then
            callback(checked)
        end
    end)
    
    cb:SetScript("OnEnter", function(self)
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    cb:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    cb.UpdateValue = function(self)
        local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
        self:SetChecked(db[dbKey])
    end
    
    return cb
end

-- Helper: Create a Slider
local function CreateSlider(parent, labelText, dbKey, minVal, maxVal, step, valueFormat, tooltipText, callback, isAlert)
    local slider = CreateFrame("Slider", "BarIndicatorSlider_" .. dbKey .. (isAlert and "_alert" or ""), parent, "OptionsSliderTemplate")
    slider:SetSize(140, 16)
    
    local titleStr = slider.Text or _G[slider:GetName() .. "Text"]
    local lowStr = slider.Low or _G[slider:GetName() .. "Low"]
    local highStr = slider.High or _G[slider:GetName() .. "High"]
    
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    
    if lowStr then lowStr:SetText(tostring(minVal)) end
    if highStr then highStr:SetText(tostring(maxVal)) end
    
    local function UpdateLabel()
        local val = slider:GetValue()
        local formatted = string.format(valueFormat or "%.1f", val)
        if titleStr then
            if slider.editBox then
                titleStr:SetText(labelText)
            else
                titleStr:SetText(labelText .. ": |cff00e5ff" .. formatted .. "|r")
            end
        end
        if slider.editBox and not slider.editBox:HasFocus() then
            slider.editBox:SetText(formatted)
        end
    end
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
        if db[dbKey] == value then
            return
        end
        if dbKey == "scale" then
            if isAlert then
                SetAlertScale(value)
            else
                SetFrameScale(value)
            end
        else
            db[dbKey] = value
            if callback then
                callback(value)
            end
        end
        UpdateLabel()
    end)
    
    slider:SetScript("OnEnter", function(self)
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    slider:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    slider.UpdateValue = function(self)
        local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
        self:SetValue(db[dbKey])
        UpdateLabel()
    end
    
    if dbKey == "scale" or dbKey == "fontSize" or dbKey == "triggerBar" or dbKey == "width" or dbKey == "height" then
        slider.editBox = CreateEditBoxForSlider(parent, slider, dbKey, minVal, maxVal, step, valueFormat, callback, isAlert)
    end
    
    return slider
end

-- Helper: Create Color Swatch grids
local function CreateColorSwatches(parent, labelText, dbKey, yOffset, isAlert)
    local labelStr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelStr:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    labelStr:SetText(labelText)
    
    local swatchButtons = {}
    
    for i, preset in ipairs(colorPresets) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(20, 20)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 150 + (i - 1) * 26, yOffset + 3)
        
        -- Color square texture
        local tex = btn:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(btn)
        tex:SetColorTexture(unpack(preset.color))
        btn.colorTexture = tex
        
        -- Hover texture
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(btn)
        highlight:SetColorTexture(1, 1, 1, 0.3)
        
        -- Active selection border
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetSize(24, 24)
        border:SetPoint("CENTER", btn, "CENTER")
        border:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        border:SetBlendMode("ADD")
        border:Hide()
        btn.border = border
        
        btn:SetScript("OnClick", function()
            local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
            db[dbKey] = CopyTable(preset.color)
            if isAlert then
                RefreshAlertStyles()
            else
                RefreshFrameStyles()
            end
            
            -- Reset selection highlight in this row
            for _, otherBtn in ipairs(swatchButtons) do
                otherBtn.border:Hide()
            end
            btn.border:Show()
        end)
        
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(preset.name, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        table.insert(swatchButtons, btn)
    end
    
    local function UpdateSelection()
        local db = isAlert and BarIndicatorDB.alert or BarIndicatorDB
        local dbColor = db[dbKey]
        if not dbColor then return end
        for i, btn in ipairs(swatchButtons) do
            local preset = colorPresets[i]
            if math.abs(dbColor[1] - preset.color[1]) < 0.01 and
               math.abs(dbColor[2] - preset.color[2]) < 0.01 and
               math.abs(dbColor[3] - preset.color[3]) < 0.01 then
                btn.border:Show()
            else
                btn.border:Hide()
            end
        end
    end
    
    return UpdateSelection
end

-- Layout Categories: Subheaders
local visHeader = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
visHeader:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -70)
visHeader:SetText("Main Indicator Settings")

local alertHeader = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
alertHeader:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 320, -70)
alertHeader:SetText("Warning Alert Settings")

-- Left Column (Main Indicator Settings)
local lockCB = CreateCheckbox(optionsFrame, "Lock Frame Position", "locked", "Locks the indicator frame so it cannot be dragged accidentally.")
lockCB:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -95)

local hideMainCB = CreateCheckbox(optionsFrame, "Hide Main Bar in Combat", "hideMainBarInCombat", "Hides the default Blizzard main action bar in combat securely.", function(val)
    UpdateMainBarCombatHiding()
end)
hideMainCB:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -125)

local showLabelCB = CreateCheckbox(optionsFrame, "Show \"BAR\" Label Text", "showBarLabel", "Toggles whether the small \"BAR\" label is displayed above the number. If hidden, the number will automatically re-center.", function(val)
    RefreshFrameStyles()
end)
showLabelCB:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -155)

local showInCombatCB = CreateCheckbox(optionsFrame, "Show Indicator in Combat", "showIndicatorInCombat", "Toggles whether our page indicator frame is shown while in combat.", function(val)
    UpdateIndicatorVisibility()
end)
showInCombatCB:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -185)

local showOutCombatCB = CreateCheckbox(optionsFrame, "Show Indicator Out of Combat", "showIndicatorOutCombat", "Toggles whether our page indicator frame is shown when not in combat.", function(val)
    UpdateIndicatorVisibility()
end)
showOutCombatCB:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -215)

local scaleSlider = CreateSlider(optionsFrame, "Frame Scale", "scale", 0.5, 3.0, 0.1, "%.1f", "Scale size of the page indicator.", function(val)
    RefreshFrameStyles()
end)
scaleSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -265)

local fontSlider = CreateSlider(optionsFrame, "Font Size", "fontSize", 12, 48, 1, "%d", "Adjust text font size of the indicator number.", function(val)
    RefreshFrameStyles()
end)
fontSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -315)

local bgSlider = CreateSlider(optionsFrame, "BG Opacity", "bgAlpha", 0.0, 1.0, 0.05, "%.2f", "Adjust opacity of the frame background.", function(val)
    RefreshFrameStyles()
end)
bgSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -365)

local borderSlider = CreateSlider(optionsFrame, "Border Opacity", "borderAlpha", 0.0, 1.0, 0.05, "%.2f", "Adjust opacity of the frame border.", function(val)
    RefreshFrameStyles()
end)
borderSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -415)

-- Right Column (Warning Alert Settings)
local alertEnabledCB = CreateCheckbox(optionsFrame, "Enable Warning Alert", "enabled", "Toggles the separate warning alert popup frame.", function(val)
    UpdateAlertVisibility()
end, true)
alertEnabledCB:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 320, -95)

local alertTriggerSlider = CreateSlider(optionsFrame, "Trigger Action Bar", "triggerBar", 1, 6, 1, "%d", "The action bar page that triggers this warning alert.", function(val)
    UpdateAlertVisibility()
end, true)
alertTriggerSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 320, -125)

local alertOnlyInCombatCB = CreateCheckbox(optionsFrame, "Only Show in Combat", "onlyInCombat", "Toggles whether this warning alert is only shown while you are in combat.", function(val)
    UpdateAlertVisibility()
end, true)
alertOnlyInCombatCB:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 320, -165)

local alertTextLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
alertTextLabel:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 320, -195)
alertTextLabel:SetText("Alert Message:")

local alertTextEB = CreateFrame("EditBox", "BarIndicatorOptionsAlertTextEB", optionsFrame, "InputBoxTemplate")
alertTextEB:SetSize(180, 20)
alertTextEB:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 325, -215)
alertTextEB:SetAutoFocus(false)
alertTextEB:SetFontObject("GameFontHighlightSmall")
alertTextEB:SetMaxLetters(24)
alertTextEB:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)
alertTextEB:SetScript("OnEditFocusLost", function(self)
    local text = self:GetText()
    if text and text ~= "" then
        BarIndicatorDB.alert.text = text
        RefreshAlertStyles()
    end
end)
alertTextEB.UpdateValue = function(self)
    self:SetText(BarIndicatorDB.alert.text or "WARNING: BAR 2!")
end

local alertScaleSlider = CreateSlider(optionsFrame, "Alert Scale", "scale", 0.5, 3.0, 0.1, "%.1f", "Scale size of the warning alert frame.", function(val)
    RefreshAlertStyles()
end, true)
alertScaleSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 320, -250)

local alertFontSlider = CreateSlider(optionsFrame, "Alert Font Size", "fontSize", 12, 48, 1, "%d", "Adjust text font size of the warning alert frame.", function(val)
    RefreshAlertStyles()
end, true)
alertFontSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 320, -295)

local alertWidthSlider = CreateSlider(optionsFrame, "Alert Width", "width", 60, 400, 5, "%d", "Adjust width (X-axis size) of the warning alert box.", function(val)
    RefreshAlertStyles()
end, true)
alertWidthSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 320, -340)

local alertHeightSlider = CreateSlider(optionsFrame, "Alert Height", "height", 15, 150, 2, "%d", "Adjust height (Y-axis size) of the warning alert box.", function(val)
    RefreshAlertStyles()
end, true)
alertHeightSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 320, -385)

-- Colors Presets Section
local colorLine = optionsFrame:CreateTexture(nil, "ARTWORK")
colorLine:SetSize(580, 1)
colorLine:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -440)
colorLine:SetColorTexture(0.3, 0.3, 0.3, 0.4)

local colorHeader = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
colorHeader:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -455)
colorHeader:SetText("Active Color Presets")

local updateBar1ColorSelection = CreateColorSwatches(optionsFrame, "Bar 1 Color:", "bar1Color", -475, false)
local updateBar2ColorSelection = CreateColorSwatches(optionsFrame, "Bar 2 Color:", "bar2Color", -500, false)
local updateAlertColorSelection = CreateColorSwatches(optionsFrame, "Alert Color:", "color", -525, true)

-- Action Buttons: Reset Options
local buttonLine = optionsFrame:CreateTexture(nil, "ARTWORK")
buttonLine:SetSize(580, 1)
buttonLine:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -555)
buttonLine:SetColorTexture(0.3, 0.3, 0.3, 0.4)

local resetPosBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
resetPosBtn:SetSize(130, 24)
resetPosBtn:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -570)
resetPosBtn:SetText("Reset Position")
resetPosBtn:SetScript("OnClick", function()
    BarIndicatorDB.point = defaults.point
    BarIndicatorDB.relativePoint = defaults.relativePoint
    BarIndicatorDB.posX = defaults.posX
    BarIndicatorDB.posY = defaults.posY
    
    BarIndicatorDB.alert.point = defaults.alert.point
    BarIndicatorDB.alert.relativePoint = defaults.alert.relativePoint
    BarIndicatorDB.alert.posX = defaults.alert.posX
    BarIndicatorDB.alert.posY = defaults.alert.posY
    
    RestoreFramePosition()
    RestoreAlertPosition()
    PrintMsg("Positions reset to default coordinates.")
end)

local resetAllBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
resetAllBtn:SetSize(130, 24)
resetAllBtn:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 165, -570)
resetAllBtn:SetText("Reset Defaults")
resetAllBtn:SetScript("OnClick", function()
    if InCombatLockdown() then
        PrintMsg("|cffff3333Error: Cannot reset options during combat!|r")
        return
    end
    
    -- Restore database defaults
    BarIndicatorDB = CopyTable(defaults)
    BarIndicatorDB.posVersion = 2
    
    -- Refresh Option frame controls
    lockCB:UpdateValue()
    hideMainCB:UpdateValue()
    showLabelCB:UpdateValue()
    showInCombatCB:UpdateValue()
    showOutCombatCB:UpdateValue()
    scaleSlider:UpdateValue()
    fontSlider:UpdateValue()
    bgSlider:UpdateValue()
    borderSlider:UpdateValue()
    updateBar1ColorSelection()
    updateBar2ColorSelection()
    
    alertEnabledCB:UpdateValue()
    alertTriggerSlider:UpdateValue()
    alertOnlyInCombatCB:UpdateValue()
    alertTextEB:UpdateValue()
    alertScaleSlider:UpdateValue()
    alertFontSlider:UpdateValue()
    alertWidthSlider:UpdateValue()
    alertHeightSlider:UpdateValue()
    updateAlertColorSelection()
    
    -- Refresh actual frame visuals
    RefreshFrameStyles()
    UpdateIndicatorVisibility()
    UpdateMainBarCombatHiding()
    
    RefreshAlertStyles()
    UpdateAlertVisibility()
    
    PrintMsg("All preferences reset to factory defaults.")
end)

-- Hook options frame to populate values on display
optionsFrame:SetScript("OnShow", function(self)
    lockCB:UpdateValue()
    hideMainCB:UpdateValue()
    showLabelCB:UpdateValue()
    showInCombatCB:UpdateValue()
    showOutCombatCB:UpdateValue()
    scaleSlider:UpdateValue()
    fontSlider:UpdateValue()
    bgSlider:UpdateValue()
    borderSlider:UpdateValue()
    updateBar1ColorSelection()
    updateBar2ColorSelection()
    
    alertEnabledCB:UpdateValue()
    alertTriggerSlider:UpdateValue()
    alertOnlyInCombatCB:UpdateValue()
    alertTextEB:UpdateValue()
    alertScaleSlider:UpdateValue()
    alertFontSlider:UpdateValue()
    alertWidthSlider:UpdateValue()
    alertHeightSlider:UpdateValue()
    updateAlertColorSelection()
end)

-- Register within WoW Settings menu categories (Retail & Classic compatible)
retailCategory = nil
if Settings and Settings.RegisterCanvasLayoutCategory then
    retailCategory = Settings.RegisterCanvasLayoutCategory(optionsFrame, "BarIndicator")
    Settings.RegisterAddOnCategory(retailCategory)
else
    InterfaceOptions_AddCategory(optionsFrame)
end

----------------------------------------------------
-- Slash Commands Handler
----------------------------------------------------

SLASH_BARINDICATOR1 = "/barindicator"
SLASH_BARINDICATOR2 = "/bi"

SlashCmdList["BARINDICATOR"] = function(msg)
    msg = string.lower(msg or "")
    local args = {}
    for word in string.gmatch(msg, "%S+") do
        table.insert(args, word)
    end
    
    local cmd = args[1]
    
    if cmd == "lock" then
        BarIndicatorDB.locked = not BarIndicatorDB.locked
        if BarIndicatorDB.locked then
            PrintMsg("Frame is now |cff00ff00LOCKED|r.")
        else
            PrintMsg("Frame is now |cffffff00UNLOCKED|r. Hold |cff00e5ffShift|r and drag to move.")
        end
        
    elseif cmd == "hide" or cmd == "combatfade" then
        if InCombatLockdown() then
            PrintMsg("|cffff3333Error: Cannot change combat settings during combat!|r")
            return
        end
        BarIndicatorDB.hideMainBarInCombat = not BarIndicatorDB.hideMainBarInCombat
        UpdateMainBarCombatHiding()
        if BarIndicatorDB.hideMainBarInCombat then
            PrintMsg("Main Action Bar will now |cff00ff00HIDE|r in combat.")
        else
            PrintMsg("Main Action Bar will now |cffffff00remain visible|r in combat.")
        end
        
    elseif cmd == "scale" then
        local scaleVal = tonumber(args[2])
        if scaleVal and scaleVal >= 0.5 and scaleVal <= 3.0 then
            SetFrameScale(scaleVal)
            PrintMsg("Scale set to |cff00e5ff" .. scaleVal .. "|r.")
        else
            PrintMsg("Usage: |cff00e5ff/bi scale <0.5 to 3.0>|r (current: " .. BarIndicatorDB.scale .. ")")
        end
        
    elseif cmd == "config" or cmd == "options" or cmd == "menu" then
        if Settings and Settings.OpenToCategory and retailCategory then
            Settings.OpenToCategory(retailCategory:GetID())
        else
            InterfaceOptionsFrame_OpenToCategory(optionsFrame)
        end
        
    elseif cmd == "reset" then
        if InCombatLockdown() then
            PrintMsg("|cffff3333Error: Cannot reset options during combat!|r")
            return
        end
        BarIndicatorDB = CopyTable(defaults)
        BarIndicatorDB.posVersion = 2
        RefreshFrameStyles()
        UpdateIndicatorVisibility()
        UpdateMainBarCombatHiding()
        
        RefreshAlertStyles()
        UpdateAlertVisibility()
        
        PrintMsg("All preferences and positions reset to defaults.")
        
    else
        -- Help Printout
        print("|cff00e5ffBarIndicator Commands:|r")
        print("  |cff00e5ff/bi config|r - Open the addon Options configuration menu")
        print("  |cff00e5ff/bi lock|r - Toggle frame dragging lock")
        print("  |cff00e5ff/bi hide|r - Toggle default main action bar hiding in combat")
        print("  |cff00e5ff/bi scale <num>|r - Set HUD scale (0.5 to 3.0)")
        print("  |cff00e5ff/bi reset|r - Reset frame position and settings to defaults")
    end
end

----------------------------------------------------
-- Edit Mode Manager Integration
----------------------------------------------------

local function OnEditModeEnter()
    C_Timer.After(0, function()
        UnregisterStateDriver(frame, "visibility")
        frame:Show()
        if alertFrame then
            UnregisterStateDriver(alertFrame, "visibility")
            alertFrame:Show()
        end
    end)
    editOverlay:Show()
    if alertOverlayAlert then
        alertOverlayAlert:Show()
    end
end

local function OnEditModeExit()
    editOverlay:Hide()
    if alertOverlayAlert then
        alertOverlayAlert:Hide()
    end
    if editDialog then
        editDialog:Hide()
    end
    C_Timer.After(0, function()
        UpdateIndicatorVisibility()
        UpdateAlertVisibility()
    end)
end

if EditModeManagerFrame then
    EditModeManagerFrame:HookScript("OnShow", OnEditModeEnter)
    EditModeManagerFrame:HookScript("OnHide", OnEditModeExit)
    
    if EditModeManagerFrame:IsShown() then
        OnEditModeEnter()
    end
end
