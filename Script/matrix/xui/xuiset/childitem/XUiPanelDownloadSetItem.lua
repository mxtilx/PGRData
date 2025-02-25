local XUiPanelDownloadSetItem = XClass(nil, "XUiPanelDownloadSetItem")


function XUiPanelDownloadSetItem:Ctor(ui, parent)
    self.GameObject = ui.gameObject
    self.Transform = ui.transform
    self.Parent = parent
    XTool.InitUiObject(self)

    self.HAS_DOWNLOAD_TXT =  CS.XTextManager.GetText("DlcHasDownloaded")
    self.CAN_DOWNLOAD_TXT =  CS.XTextManager.GetText("DlcCanDownload")

    if self.CanDownloadTxt then
        self.CanDownloadTxt.text = self.CAN_DOWNLOAD_TXT
        self.DownloadedTxt.text = self.HAS_DOWNLOAD_TXT
    end

    self.layoutGroup = ui.transform:GetComponent("XAutoLayoutGroup")
    self.part2 = ui.transform:Find("part2")
    self.part3 = ui.transform:Find("part3")
end

local GetSizeAndUnit = function(size)
        local unit = "KB"
        local num = size / 1024
        if (num > 100) then
            unit = "MB"
            num = num / 1024
        end
        return math.ceil(num),unit
    end

function XUiPanelDownloadSetItem:Setup(dlcItemData, index)
   
    self.index = index
    self.isCurrent = isCurrent

    self.BtnSelf.CallBack = function()
        self.Parent:OnClickItem(index)
    end
    self.txtTitle.text = dlcItemData:GetTitle()
    local dlcIds = dlcItemData:GetDlcId()
    local size = XDataCenter.DlcManager.GetDownloadSize(dlcIds)
    local num, unit = GetSizeAndUnit(size)
    self.txtSize.text = num .. unit

    local hasDownload = dlcItemData:HasDownloaded()

    if self.CanDownloadTxt then
        self.CanDownloadTxt.gameObject:SetActiveEx(not hasDownload)
        self.DownloadedTxt.gameObject:SetActiveEx(hasDownload)
    end

    if self.txtTip then
       
        self.txtTip.text = hasDownload and self.HAS_DOWNLOAD_TXT or self.CAN_DOWNLOAD_TXT
    end

    if self.txtDesc then
        self.txtDesc.text = dlcItemData:GetDesc()
    end

    if self.BtnDownload then
        if hasDownload then
            self.part2.gameObject:SetActiveEx(false)
            self.part3.gameObject:SetActiveEx(false)
            self.BtnDownload:SetButtonState(CS.UiButtonState.Disable)
            self.BtnDownload.CallBack = nil
        else
            self.part2.gameObject:SetActiveEx(true)
            self.part3.gameObject:SetActiveEx(true)
            self.BtnDownload:SetButtonState(CS.UiButtonState.Normal)
            dlcItemData:SetProgressAndDoneCb(nil, function()
                self.Parent:OnClickItem(index)
            end)
            self.BtnDownload.CallBack = function()
                --XLog.Debug("click:"..index)
                XDataCenter.DlcManager.DownloadDlc(dlcIds, nil,function()
                    self.Parent:OnClickItem(index)
                end)
            end
        end
      
    end

    if self.layoutGroup then
        self.layoutGroup.enabled = true

        CS.XTool.WaitForEndOfFrame(function()
            --CS.XLog.Debug("SetDirty:"..self.index)
            if self and self.layoutGroup then
                self.layoutGroup.enabled = false

                CS.XTool.WaitForEndOfFrame(function()
                    --CS.XLog.Debug("SetDirty:"..self.index)
                    if self and self.layoutGroup then
                        self.layoutGroup.enabled = true
                    end
                end)
            end
           
        end)
    end
   

   
end



return XUiPanelDownloadSetItem