local _, T = ...

-- Shared by both flavors (Core.lua and Core_Retail.lua each own a lifecycle,
-- but the commands are identical).
SLASH_BGSTAT1, SLASH_BGSTAT2 = "/bgstat", "/bgs"
SlashCmdList.BGSTAT = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" then
        T.ui.toggle()
    elseif msg == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("BgStat: /bgstat (toggle window) | /bgstat last | /bgstat history | /bgstat classes | /bgstat specs | /bgstat kills | /bgstat trends | /bgstat send | /bgstat config | /bgstat clear")
    elseif msg == "last" or msg == "report" then
        T.ui.show(1)
    elseif msg == "history" then
        T.ui.show(2)
    elseif msg == "classes" then
        T.ui.show(3)
    elseif msg == "specs" then
        T.ui.show(4)
    elseif msg == "kills" then
        T.ui.show(5)
    elseif msg == "trends" then
        T.ui.show(6)
    elseif msg == "config" or msg == "options" then
        T.options.open()
    elseif msg == "send" then
        T.report.send_to_chat()
    elseif msg == "clear" then
        T.history.delete_all()
        DEFAULT_CHAT_FRAME:AddMessage("BgStat: history cleared")
        T.ui.refresh_active()
    else
        DEFAULT_CHAT_FRAME:AddMessage("BgStat: unknown command - try /bgstat help")
    end
end
